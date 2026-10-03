"""PyTorch AI engine (NVIDIA CUDA): Real-ESRGAN upscaling + CodeFormer face restoration.

Frames stream FFmpeg -> GPU -> FFmpeg: raw RGB in, YUV 4:2:0 out for NVENC.
Everything between (AI model, resize, faces, sharpen, color, temporal smoothing,
dithering) runs on the GPU. Upscaling runs on TensorRT when available, but only
after it passes a quality check against PyTorch on the first frame.
"""

from __future__ import annotations

import importlib.util
import queue
import sys
import threading
import types
import warnings
from pathlib import Path
from typing import Callable, Optional

import numpy as np
import torch

from . import gpu_post

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

# Face size used by CodeFormer / GFPGAN.
FACE_SIZE = 512
# TensorRT must match PyTorch at least this closely (dB PSNR; 45 dB = under 0.6% average difference).
TRT_MIN_PSNR = 45.0


def _load_descriptor(path: Path, device: torch.device, half: bool):
    import spandrel
    import spandrel_extra_arches

    try:
        spandrel_extra_arches.install()
    except Exception:  # noqa: BLE001 - already installed
        pass
    desc = spandrel.ModelLoader(device=device).load_from_file(str(path))
    desc.eval()
    use_half = half and desc.supports_half
    if use_half:
        desc.half()
    return desc, use_half


def psnr(a: torch.Tensor, b: torch.Tensor) -> float:
    mse = float((a.float() - b.float()).square().mean())
    return 100.0 if mse <= 1e-12 else 10.0 * float(np.log10(1.0 / mse))


class Upscaler:
    """Single-image super-resolution with automatic tiling when VRAM runs short."""

    def __init__(self, model_path: Path, device: torch.device, half: bool = True, tile: int = 0):
        self.device = device
        self.desc, self.half = _load_descriptor(model_path, device, half)
        self.scale = int(self.desc.scale)
        self.tile = tile  # 0 = whole frame

    def _run(self, x: torch.Tensor) -> torch.Tensor:
        if not self.tile or (x.shape[2] <= self.tile and x.shape[3] <= self.tile):
            return self.desc(x)
        s, t, pad = self.scale, self.tile, 16
        _, c, h, w = x.shape
        out = x.new_zeros((1, c, h * s, w * s))
        for y0 in range(0, h, t):
            for x0 in range(0, w, t):
                y1, x1 = min(y0 + t, h), min(x0 + t, w)
                py0, px0 = max(y0 - pad, 0), max(x0 - pad, 0)
                py1, px1 = min(y1 + pad, h), min(x1 + pad, w)
                o = self.desc(x[:, :, py0:py1, px0:px1])
                oy, ox = (y0 - py0) * s, (x0 - px0) * s
                out[:, :, y0 * s:y1 * s, x0 * s:x1 * s] = o[:, :, oy:oy + (y1 - y0) * s, ox:ox + (x1 - x0) * s]
        return out

    @torch.inference_mode()
    def __call__(self, x: torch.Tensor) -> torch.Tensor:
        x = x.half() if self.half else x.float()
        while True:
            try:
                return self._run(x)
            except torch.cuda.OutOfMemoryError:
                torch.cuda.empty_cache()
                new_tile = max(self.tile // 2, 128) if self.tile else 512
                if new_tile == self.tile:
                    raise
                self.tile = new_tile  # keep the smaller tile for the rest of the video


def _face_helper_class():
    # facexlib's package __init__ pulls in tracking modules (filterpy/numba) we do not need;
    # register a bare package so only the detection / parsing / helper modules are imported.
    if "facexlib" not in sys.modules:
        spec = importlib.util.find_spec("facexlib")
        if spec is None or not spec.submodule_search_locations:
            raise ImportError("facexlib is not installed")
        pkg = types.ModuleType("facexlib")
        pkg.__path__ = list(spec.submodule_search_locations)
        sys.modules["facexlib"] = pkg
    from facexlib.utils.face_restoration_helper import FaceRestoreHelper

    return FaceRestoreHelper


class FaceRestorer:
    """Detect faces on the original frame, restore them with CodeFormer (batched, on the GPU)
    and paste them onto the output frame on the GPU. Landmarks are smoothed between frames."""

    def __init__(self, model_path: Path, weights_dir: Path, device: torch.device,
                 fidelity: float = 0.7, half: bool = True):
        helper_cls = _face_helper_class()
        self.helper = helper_cls(1, face_size=FACE_SIZE, crop_ratio=(1, 1), det_model="retinaface_resnet50",
                                 save_ext="png", use_parse=True, device=device, model_rootpath=str(weights_dir))
        self.desc, self.half = _load_descriptor(model_path, device, half)
        self.device = device
        self.fidelity = fidelity
        self.prev: list[np.ndarray] = []

    def _smooth(self, landmarks: list[np.ndarray]) -> list[np.ndarray]:
        out = []
        for lm in landmarks:
            eye = float(np.linalg.norm(lm[0] - lm[1])) or 1.0
            best = min(self.prev, key=lambda p: float(np.abs(p - lm).mean()), default=None)
            if best is not None and float(np.abs(best - lm).mean()) < 0.08 * eye:
                lm = 0.6 * best + 0.4 * lm  # nearly still face: damp detector jitter
            out.append(lm)
        self.prev = out
        return out

    @torch.inference_mode()
    def _restore(self, faces: torch.Tensor) -> torch.Tensor:
        t = faces.half() if self.half else faces.float()
        if self.desc.architecture.id == "CodeFormer":
            # CodeFormer works on [-1, 1]; weight = fidelity (higher keeps more of the original identity).
            out = self.desc.model((t - 0.5) / 0.5, weight=self.fidelity, adain=True)[0]
            out = out * 0.5 + 0.5
        else:
            out = torch.cat([self.desc(t[i:i + 1]) for i in range(t.shape[0])])
        return out.clamp_(0, 1)

    @torch.inference_mode()
    def apply(self, lr_rgb: np.ndarray, frame: torch.Tensor, fx: float, fy: float) -> torch.Tensor:
        h = self.helper
        h.clean_all()
        h.read_image(np.ascontiguousarray(lr_rgb[:, :, ::-1]))
        if h.get_face_landmarks_5(only_center_face=False, resize=640, eye_dist_threshold=5) == 0:
            self.prev = []
            return frame
        h.all_landmarks_5 = self._smooth(h.all_landmarks_5)
        h.align_warp_face()
        crops = torch.from_numpy(np.stack([c[:, :, ::-1] for c in h.cropped_faces]).copy())
        crops = crops.to(self.device).permute(0, 3, 1, 2).float().div_(255.0)
        restored = self._restore(crops)
        masks = gpu_post.face_masks(h.face_parse, restored)
        return gpu_post.paste_faces(frame, restored, masks, h.affine_matrices, fx, fy)


class Engine:
    def __init__(self, sr_model: Path, sr_name: str, face_model: Optional[Path], weights_dir: Path,
                 in_size: tuple[int, int], out_size: tuple[int, int], post: dict,
                 fidelity: float = 0.7, tile: int = 0, trt_cache: Optional[Path] = None,
                 report: Optional[Callable[[str], None]] = None, device: Optional[str] = None):
        dev = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
        self.device = dev
        half = dev.type == "cuda"
        if dev.type == "cuda":
            torch.backends.cudnn.benchmark = True
            # Leave VRAM headroom for Windows / the display so the PC stays responsive.
            torch.cuda.set_per_process_memory_fraction(0.9)
        self.in_w, self.in_h = in_size
        self.out_w, self.out_h = out_size
        self.post = post
        self.upscaler = Upscaler(sr_model, dev, half=half, tile=tile)
        self.scale = self.upscaler.scale
        self.trt = None
        self.backend = "PyTorch"
        if trt_cache is not None and dev.type == "cuda":
            from . import trt_backend

            if trt_backend.available():
                try:
                    self.trt = trt_backend.TRTUpscaler(
                        self.upscaler.desc.model, sr_name, self.scale, self.in_w, self.in_h, trt_cache,
                        on_build=(lambda: report("optimizing for GPU")) if report else None)
                    self.backend = "TensorRT"
                except Exception:  # noqa: BLE001 - not enough VRAM, unsupported layer...: PyTorch is fine
                    self.trt = None
        self.faces = FaceRestorer(face_model, weights_dir, dev, fidelity, half) if face_model else None
        self.temporal = gpu_post.TemporalSmoother(post.get("temporal", 0.45))

    def _upscale(self, x: torch.Tensor) -> torch.Tensor:
        if self.trt is None:
            return self.upscaler(x)
        try:
            if self.trt.verified is None:
                # First frame on a new engine: it must match PyTorch, otherwise it is never used.
                ref, out = self.upscaler(x), self.trt(x)
                ok = psnr(ref, out) >= TRT_MIN_PSNR
                self.trt.mark(ok)
                if not ok:
                    self.trt, self.backend = None, "PyTorch"
                    return ref
                return out
            return self.trt(x)
        except Exception:  # noqa: BLE001 - runtime failure: continue on PyTorch
            self.trt, self.backend = None, "PyTorch"
            return self.upscaler(x)

    @torch.inference_mode()
    def process(self, rgb: np.ndarray) -> np.ndarray:
        x = torch.from_numpy(rgb).to(self.device, non_blocking=True).permute(2, 0, 1).unsqueeze(0)
        x = x.half() if self.device.type == "cuda" else x.float()
        x = x.div_(255.0)
        y = gpu_post.resize(self._upscale(x), self.out_w, self.out_h)
        if self.faces is not None:
            y = self.faces.apply(rgb, y, self.out_w / self.in_w, self.out_h / self.in_h)
        y = gpu_post.cas(y, self.post.get("sharpen", 0.0))
        y = gpu_post.color(y, self.post.get("color", {}))
        y = self.temporal(y)
        return gpu_post.to_yuv420(y).cpu().numpy()


def run_stream(engine: Engine, reader, writer, width: int, height: int, total: int,
               progress: Callable[[int], None]) -> int:
    """Read raw RGB frames from reader.stdout, enhance, write YUV to writer.stdin. Returns frame count."""
    frame_bytes = width * height * 3
    q_in: "queue.Queue[Optional[bytearray]]" = queue.Queue(maxsize=6)
    q_out: "queue.Queue[Optional[np.ndarray]]" = queue.Queue(maxsize=6)
    errors: list[BaseException] = []

    def read_loop() -> None:
        try:
            while True:
                buf = bytearray(frame_bytes)  # writable buffer -> zero-copy numpy/torch
                view, got = memoryview(buf), 0
                while got < frame_bytes:
                    n = reader.stdout.readinto(view[got:])
                    if not n:
                        break
                    got += n
                if got < frame_bytes:
                    break
                q_in.put(buf)
        except BaseException as e:  # noqa: BLE001
            errors.append(e)
        finally:
            q_in.put(None)

    def write_loop() -> None:
        try:
            while True:
                frame = q_out.get()
                if frame is None:
                    break
                writer.stdin.write(memoryview(frame))
        except BaseException as e:  # noqa: BLE001
            errors.append(e)
        finally:
            try:
                writer.stdin.close()
            except OSError:
                pass

    def put_out(item) -> None:
        # Never block forever if the writer died (e.g. the encoder crashed).
        while True:
            try:
                q_out.put(item, timeout=0.5)
                return
            except queue.Full:
                if not wt.is_alive():
                    return

    rt = threading.Thread(target=read_loop, daemon=True)
    wt = threading.Thread(target=write_loop, daemon=True)
    rt.start()
    wt.start()
    done = 0
    try:
        while not errors:
            buf = q_in.get()
            if buf is None:
                break
            frame = np.frombuffer(buf, dtype=np.uint8).reshape(height, width, 3)
            put_out(engine.process(frame))
            done += 1
            progress(done)
    finally:
        put_out(None)
        wt.join(timeout=60)
    if errors:
        raise errors[0]
    return done
