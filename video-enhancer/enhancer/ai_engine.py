"""PyTorch AI engine (NVIDIA CUDA): Real-ESRGAN upscaling + CodeFormer face restoration.

Frames stream FFmpeg -> GPU -> FFmpeg as raw RGB, so nothing is written to disk.
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

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

# Face size used by CodeFormer / GFPGAN.
FACE_SIZE = 512


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
    def __call__(self, rgb: np.ndarray) -> np.ndarray:
        x = torch.from_numpy(rgb).to(self.device, non_blocking=True).permute(2, 0, 1).unsqueeze(0)
        x = x.half() if self.half else x.float()
        x = x.div_(255.0)
        while True:
            try:
                y = self._run(x)
                break
            except torch.cuda.OutOfMemoryError:
                torch.cuda.empty_cache()
                new_tile = max(self.tile // 2, 128) if self.tile else 512
                if new_tile == self.tile:
                    raise
                self.tile = new_tile  # keep the smaller tile for the rest of the video
        y = y.clamp_(0, 1).mul_(255.0).round_().to(torch.uint8)
        return y.squeeze(0).permute(1, 2, 0).contiguous().cpu().numpy()


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
    """Detect faces on the original frame, restore them with CodeFormer/GFPGAN and paste them
    onto the upscaled frame. Landmarks are smoothed between frames to avoid jitter."""

    def __init__(self, model_path: Path, weights_dir: Path, device: torch.device, upscale: int,
                 fidelity: float = 0.7, half: bool = True):
        helper_cls = _face_helper_class()
        self.helper = helper_cls(upscale, face_size=FACE_SIZE, crop_ratio=(1, 1), det_model="retinaface_resnet50",
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
    def _restore(self, face_bgr: np.ndarray) -> np.ndarray:
        t = torch.from_numpy(face_bgr[:, :, ::-1].copy()).to(self.device).permute(2, 0, 1).unsqueeze(0)
        t = (t.half() if self.half else t.float()).div_(255.0)
        model = self.desc.model
        if self.desc.architecture.id == "CodeFormer":
            # CodeFormer works on [-1, 1]; weight = fidelity (higher keeps more of the original identity).
            out = model((t - 0.5) / 0.5, weight=self.fidelity, adain=True)[0]
            out = (out * 0.5 + 0.5)
        else:
            out = self.desc(t)
        out = out.clamp_(0, 1).mul_(255.0).round_().to(torch.uint8)
        return out.squeeze(0).permute(1, 2, 0).cpu().numpy()[:, :, ::-1].copy()

    def __call__(self, lr_rgb: np.ndarray, sr_rgb: np.ndarray) -> np.ndarray:
        h = self.helper
        h.clean_all()
        h.read_image(np.ascontiguousarray(lr_rgb[:, :, ::-1]))
        if h.get_face_landmarks_5(only_center_face=False, resize=640, eye_dist_threshold=5) == 0:
            self.prev = []
            return sr_rgb
        h.all_landmarks_5 = self._smooth(h.all_landmarks_5)
        h.align_warp_face()
        for face in h.cropped_faces:
            h.add_restored_face(self._restore(face))
        h.get_inverse_affine(None)
        out = h.paste_faces_to_input_image(upsample_img=np.ascontiguousarray(sr_rgb[:, :, ::-1]))
        return np.ascontiguousarray(out[:, :, ::-1])


class Engine:
    def __init__(self, sr_model: Path, face_model: Optional[Path], weights_dir: Path,
                 fidelity: float = 0.7, tile: int = 0, device: Optional[str] = None):
        dev = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
        half = dev.type == "cuda"
        if dev.type == "cuda":
            torch.backends.cudnn.benchmark = True
        self.upscaler = Upscaler(sr_model, dev, half=half, tile=tile)
        self.scale = self.upscaler.scale
        self.faces = (FaceRestorer(face_model, weights_dir, dev, self.scale, fidelity, half)
                      if face_model else None)

    def process(self, rgb: np.ndarray) -> np.ndarray:
        sr = self.upscaler(rgb)
        if self.faces is not None:
            sr = self.faces(rgb, sr)
        return sr


def run_stream(engine: Engine, reader, writer, width: int, height: int, total: int,
               progress: Callable[[int], None]) -> int:
    """Read raw RGB frames from reader.stdout, enhance, write to writer.stdin. Returns frame count."""
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
                writer.stdin.write(frame.tobytes())
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
