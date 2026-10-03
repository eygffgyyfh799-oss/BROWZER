"""Video enhancement pipeline.

GPU path (NVIDIA / any Vulkan GPU, used automatically when available):
  1. FFmpeg decodes, converts HDR to SDR, cleans blocking/noise and exports
     constant-frame-rate frames.
  2. RIFE (GPU) interpolates frames for the FPS boost.
  3. Real-ESRGAN (GPU) upscales frame by frame, in chunks so disk usage stays low.
  4. Each chunk is encoded with NVENC (or x264), with a deflicker pass for
     temporal consistency, then the chunks are joined and the audio is muxed.

CPU path (fallback): a single FFmpeg filter graph with temporal denoise,
deblocking, Lanczos upscaling, sharpening, color correction and
motion-compensated interpolation.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

from .bootstrap import NO_WINDOW

# Helper processes run below normal priority: full speed when the PC is idle,
# but Windows and the desktop always stay responsive.
LOW_PRIORITY = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
from .presets import ENGINES, FPS_OPTIONS, PRESETS, RESOLUTIONS

ProgressFn = Callable[[float, str], None]

SUPPORTED_EXTENSIONS = {".mp4", ".mov", ".webm", ".mkv", ".avi", ".m4v"}
CHUNK_FRAMES = 240  # frames upscaled + encoded per chunk (keeps temp disk usage small)


class EnhanceError(RuntimeError):
    pass


@dataclass
class VideoInfo:
    width: int
    height: int
    fps: float
    duration: float
    has_audio: bool
    frames: int = 0
    rate: str = "30"     # exact frame rate as FFmpeg rational, e.g. 30000/1001
    hdr: bool = False


@dataclass
class EnhanceOptions:
    engine: str = "standard"        # standard | pro
    resolution: str = "1080p"       # 1080p | 4k
    fps: str = "original"           # original | 30 | 60
    preset: str = "ugc"             # ai | old_film | ugc | none
    use_ai: Optional[bool] = None   # None = auto (use GPU AI when available)
    faces: bool = True              # CodeFormer face recovery (PyTorch engine)
    crf: Optional[int] = None
    extra: dict = field(default_factory=dict)

    def validate(self) -> None:
        if self.engine not in ENGINES:
            raise EnhanceError(f"Unknown engine '{self.engine}'. Choose: {', '.join(ENGINES)}")
        if self.resolution not in RESOLUTIONS:
            raise EnhanceError(f"Unknown resolution '{self.resolution}'. Choose: {', '.join(RESOLUTIONS)}")
        if self.fps not in FPS_OPTIONS:
            raise EnhanceError(f"Unknown fps '{self.fps}'. Choose: {', '.join(FPS_OPTIONS)}")
        if self.preset not in PRESETS:
            raise EnhanceError(f"Unknown preset '{self.preset}'. Choose: {', '.join(PRESETS)}")


# --------------------------------------------------------------------------- tools

def find_ffmpeg() -> tuple[str, str]:
    from .bootstrap import local_ffmpeg

    if os.environ.get("FFMPEG_PATH") and os.environ.get("FFPROBE_PATH"):
        return os.environ["FFMPEG_PATH"], os.environ["FFPROBE_PATH"]
    local = local_ffmpeg()
    if local:
        return local
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise EnhanceError(
            "FFmpeg was not found. Run 'python -m enhancer setup' to install it automatically."
        )
    return ffmpeg, ffprobe


def find_realesrgan() -> Optional[str]:
    from .bootstrap import load_state, local_realesrgan

    path = os.environ.get("REALESRGAN_PATH")
    if path and Path(path).exists():
        return path
    if not load_state().get("ai_ok", True):  # installed but no working GPU on this machine
        return None
    return local_realesrgan() or shutil.which("realesrgan-ncnn-vulkan")


def find_rife() -> Optional[str]:
    from .bootstrap import load_state, local_rife

    path = os.environ.get("RIFE_PATH")
    if path and Path(path).exists():
        return path
    if not load_state().get("rife_ok", False):
        return None
    return local_rife()


_TORCH_STATUS: Optional[bool] = None


def torch_engine_available() -> bool:
    """PyTorch + CUDA engine (installed by setup on NVIDIA GPUs)."""
    global _TORCH_STATUS
    if _TORCH_STATUS is None:
        from .bootstrap import ai_models_ready

        try:
            import torch  # noqa: F401
            import spandrel  # noqa: F401

            gpu_ok = torch.cuda.is_available() or bool(os.environ.get("ENHANCER_DEV_CPU"))
            _TORCH_STATUS = gpu_ok and ai_models_ready()
        except Exception:  # noqa: BLE001 - not installed / broken install
            _TORCH_STATUS = False
    return _TORCH_STATUS


def nvenc_available() -> bool:
    from .bootstrap import load_state

    return bool(load_state().get("nvenc_ok", False))


def probe(path: str | Path) -> VideoInfo:
    _, ffprobe = find_ffmpeg()
    cmd = [ffprobe, "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                            creationflags=NO_WINDOW)
    if result.returncode != 0:
        raise EnhanceError(f"Cannot read video: {result.stderr.strip() or 'unknown error'}")
    data = json.loads(result.stdout)
    video = next((s for s in data.get("streams", []) if s.get("codec_type") == "video"), None)
    if not video:
        raise EnhanceError("The file does not contain a video stream.")
    has_audio = any(s.get("codec_type") == "audio" for s in data.get("streams", []))

    def parse_rate(rate: str) -> float:
        try:
            num, den = rate.split("/")
            return float(num) / float(den) if float(den) else 0.0
        except (ValueError, ZeroDivisionError):
            return 0.0

    rate = video.get("avg_frame_rate", "0/0")
    fps = parse_rate(rate)
    if not 1 <= fps <= 240:
        rate = video.get("r_frame_rate", "30/1")
        fps = parse_rate(rate)
    if not 1 <= fps <= 240:
        rate, fps = "30", 30.0
    duration = float(video.get("duration") or data.get("format", {}).get("duration") or 0)
    width, height = int(video["width"]), int(video["height"])
    if _rotation(video) in (90, 270):
        width, height = height, width
    hdr = video.get("color_transfer") in ("smpte2084", "arib-std-b67")
    return VideoInfo(width, height, fps, duration, has_audio, int(duration * fps), rate, hdr)


def _rotation(stream: dict) -> int:
    rot = stream.get("tags", {}).get("rotate")
    if rot is None:
        for side in stream.get("side_data_list", []) or []:
            if "rotation" in side:
                rot = side["rotation"]
    try:
        return abs(int(float(rot))) % 360
    except (TypeError, ValueError):
        return 0


# --------------------------------------------------------------------------- planning

def target_size(info: VideoInfo, resolution: str) -> tuple[int, int]:
    """Scale so the short side matches the target (1080 / 2160), never downscale."""
    short_target = RESOLUTIONS[resolution]["short_side"]
    short_side = min(info.width, info.height)
    factor = max(1.0, short_target / short_side)
    w = int(round(info.width * factor / 2)) * 2
    h = int(round(info.height * factor / 2)) * 2
    return w, h


def target_fps(info: VideoInfo, fps_option: str) -> Optional[float]:
    wanted = FPS_OPTIONS[fps_option]
    if wanted is None or wanted <= info.fps + 0.5:
        return None
    return float(wanted)


HDR_TO_SDR = ("zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,"
              "tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv")


def build_filters(info: VideoInfo, opts: EnhanceOptions, *, stage: str = "full",
                  light: bool = False, interpolate: bool = True) -> str:
    """Build the FFmpeg filter graph.

    stage = "full"  : everything (CPU path)
    stage = "pre"   : cleanup before GPU interpolation / upscaling
    stage = "post"  : scaling to target + sharpen/color/deflicker after GPU upscaling
    light           : skip the slow CPU denoisers (Real-ESRGAN denoises itself)
    interpolate     : use FFmpeg minterpolate for the FPS boost (False when RIFE does it)
    """
    preset = PRESETS[opts.preset]
    engine = ENGINES[opts.engine]
    out_w, out_h = target_size(info, opts.resolution)
    fps = target_fps(info, opts.fps)
    chain: list[str] = []

    if stage in ("full", "pre"):
        if info.hdr:  # iPhone / Android HDR (HLG / PQ) -> natural looking SDR
            chain.append(HDR_TO_SDR)
        if preset.get("deinterlace"):
            chain.append("bwdif=mode=send_frame:deint=interlaced")
        if preset.get("deflicker"):
            chain.append(f"deflicker=size={preset['deflicker']}:mode=pm")
        # Compression artifacts (blocking) cleanup.
        if preset.get("deblock"):
            chain.append(f"deblock=filter=strong:block=8:alpha={preset['deblock']}:beta={preset['deblock']}")
        # Denoise. hqdn3d is spatio-temporal: it averages along time which keeps
        # frames consistent and avoids flicker. Pro adds non-local means.
        luma_s, chroma_s, luma_t, chroma_t = preset["denoise"]
        if light:
            luma_s, chroma_s = luma_s * 0.5, chroma_s * 0.5
        chain.append(f"hqdn3d={luma_s:g}:{chroma_s:g}:{luma_t:g}:{chroma_t:g}")
        if not light and engine["nlmeans"] and preset.get("nlmeans"):
            chain.append(f"nlmeans=s={preset['nlmeans']}:p=7:r=9")
        if not light and engine["temporal_denoise"]:
            chain.append("atadenoise=0a=0.02:0b=0.04:1a=0.02:1b=0.04:2a=0.02:2b=0.04:s=9")
        # Frame interpolation on the small frames (much cheaper than after upscaling).
        if fps and interpolate:
            chain.append(
                f"minterpolate=fps={fps:g}:mi_mode=mci:mc_mode={engine['mc_mode']}"
                f":me_mode={engine['me_mode']}:vsbmc={1 if engine['vsbmc'] else 0}:scd=fdiff"
            )

    if stage in ("full", "post"):
        if out_w != info.width or out_h != info.height or stage == "post":
            chain.append(
                f"scale={out_w}:{out_h}:flags=lanczos+accurate_rnd+full_chroma_int+full_chroma_inp"
            )
        # Detail recovery: contrast adaptive sharpening + light luma unsharp for edges/faces.
        sharpen = preset["sharpen"] * engine["sharpen_mul"] * (0.6 if light else 1.0)
        chain.append(f"cas=strength={min(1.0, sharpen):.2f}")
        if engine["edge_unsharp"] and not light:
            chain.append("unsharp=lx=5:ly=5:la=0.35:cx=3:cy=3:ca=0.0")
        # Color correction.
        c = preset["color"]
        chain.append(f"eq=contrast={c['contrast']}:brightness={c['brightness']}:saturation={c['saturation']}:gamma={c['gamma']}")
        if c.get("vibrance"):
            chain.append(f"vibrance=intensity={c['vibrance']}")
        if stage == "post":
            # Real-ESRGAN works per frame; smooth tiny frame-to-frame differences.
            chain.append("deflicker=size=5:mode=am")
            chain.append("hqdn3d=0:0:3:3")
        # Remove banding introduced by denoising and dither to 8-bit.
        chain.append("gradfun=strength=0.6:radius=16")

    if stage != "pre":
        chain.append("format=yuv420p")
    return ",".join(chain)


def encoder_args(opts: EnhanceOptions, nvenc: bool = False) -> list[str]:
    engine = ENGINES[opts.engine]
    crf = opts.crf if opts.crf is not None else engine["crf"]
    if nvenc:
        # NVIDIA hardware encoder (separate chip on the card, does not slow the AI down).
        # p6 + two-pass lookahead + adaptive quantization = near-transparent quality at very high speed.
        return [
            "-c:v", "h264_nvenc", "-preset", "p6", "-tune", "hq", "-multipass", "qres",
            "-rc", "vbr", "-cq", str(crf), "-b:v", "0", "-maxrate", "200M", "-bufsize", "400M",
            "-spatial-aq", "1", "-temporal-aq", "1", "-aq-strength", "8", "-rc-lookahead", "32",
            "-bf", "3", "-profile:v", "high", "-pix_fmt", "yuv420p",
        ]
    return [
        "-c:v", "libx264", "-preset", engine["x264_preset"], "-crf", str(crf),
        "-tune", "film", "-profile:v", "high", "-pix_fmt", "yuv420p",
    ]


# --------------------------------------------------------------------------- running

def _run_ffmpeg(cmd: list[str], duration: float, progress: Optional[ProgressFn],
                start: float, span: float, label: str) -> None:
    proc = subprocess.Popen(
        [cmd[0], "-nostdin", *cmd[1:], "-progress", "pipe:1", "-nostats"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
        encoding="utf-8", errors="replace", creationflags=NO_WINDOW | LOW_PRIORITY,
    )
    stderr_tail: list[str] = []

    def drain() -> None:
        assert proc.stderr is not None
        for line in proc.stderr:
            stderr_tail.append(line)
            if len(stderr_tail) > 40:
                stderr_tail.pop(0)

    t = threading.Thread(target=drain, daemon=True)
    t.start()
    assert proc.stdout is not None
    for line in proc.stdout:
        key, _, value = line.strip().partition("=")
        if key == "out_time_us" and duration > 0 and progress:
            try:
                frac = min(1.0, max(0.0, int(value) / 1e6 / duration))
            except ValueError:
                continue
            progress(start + span * frac, label)
    proc.wait()
    t.join(timeout=2)
    if proc.returncode != 0:
        raise EnhanceError("FFmpeg failed:\n" + "".join(stderr_tail[-15:]))


def _run_encode(build_cmd: Callable[[list[str]], list[str]], opts: EnhanceOptions, duration: float,
                progress: Optional[ProgressFn], start: float, span: float, label: str) -> None:
    """Encode with NVENC when available, retrying with x264 if the GPU encoder fails."""
    if nvenc_available():
        try:
            return _run_ffmpeg(build_cmd(encoder_args(opts, nvenc=True)), duration, progress, start, span, label)
        except EnhanceError:
            pass
    _run_ffmpeg(build_cmd(encoder_args(opts)), duration, progress, start, span, label)


def _run_gpu_tool(cmd: list[str], out_dir: Path, total: int, report: ProgressFn,
                  start: float, span: float, label: str, name: str,
                  offset: int = 0, grand_total: int = 0) -> None:
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace",
                            cwd=str(Path(cmd[0]).parent), creationflags=NO_WINDOW | LOW_PRIORITY)
    err: list[str] = []
    t = threading.Thread(target=lambda: err.extend(proc.stderr or []), daemon=True)
    t.start()
    while proc.poll() is None:
        done = sum(1 for _ in out_dir.iterdir())
        report(start + span * min(1.0, done / max(1, total)),
               f"{label} {offset + done}/{grand_total or total}")
        time.sleep(0.5)
    t.join(timeout=2)
    produced = sum(1 for _ in out_dir.iterdir())
    if proc.returncode != 0 or produced < total:
        raise EnhanceError(f"{name} failed:\n{''.join(err)[-1500:]}")


def enhance(input_path: str | Path, output_path: str | Path, opts: EnhanceOptions,
            progress: Optional[ProgressFn] = None) -> Path:
    opts.validate()
    input_path, output_path = Path(input_path), Path(output_path)
    if not input_path.exists():
        raise EnhanceError(f"Input file not found: {input_path}")
    if input_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise EnhanceError(f"Unsupported format '{input_path.suffix}'. Use MP4, MOV or WEBM.")
    output_path = output_path.with_suffix(".mp4")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    ffmpeg, _ = find_ffmpeg()
    info = probe(input_path)
    report = progress or (lambda *_: None)
    report(0.0, "analyzing")

    plan = plan_gpu(info, opts)
    if opts.use_ai and not (plan["realesrgan"] or plan["torch"]):
        raise EnhanceError(
            "AI upscaling requested but Real-ESRGAN is not available. "
            "Run 'python -m enhancer setup' or make sure your GPU supports Vulkan."
        )

    done = False
    if plan["torch"]:
        try:
            _enhance_torch(ffmpeg, input_path, output_path, info, opts, plan, report)
            done = True
        except Exception as e:  # noqa: BLE001 - fall back to the Vulkan / CPU paths
            if opts.use_ai and plan["realesrgan"] is None:
                raise EnhanceError(f"AI engine failed: {e}") from e
            report(0.0, "AI failed, using FFmpeg")
    if not done and (plan["realesrgan"] or plan["rife"]):
        try:
            _enhance_gpu(ffmpeg, input_path, output_path, info, opts, plan, report)
            done = True
        except EnhanceError:
            if opts.use_ai:  # explicitly forced: surface the error
                raise
            report(0.0, "AI failed, using FFmpeg")  # automatic fallback
    if not done:
        def build(enc: list[str]) -> list[str]:
            return [ffmpeg, "-y", "-hide_banner", "-i", str(input_path),
                    "-map", "0:v:0", "-map", "0:a?", "-vf", build_filters(info, opts),
                    *enc, "-movflags", "+faststart", "-c:a", "aac", "-b:a", "192k", str(output_path)]
        _run_encode(build, opts, info.duration, report, 0.02, 0.98, "enhancing")

    report(1.0, "done")
    return output_path


def plan_gpu(info: VideoInfo, opts: EnhanceOptions) -> dict:
    """Decide which GPU tools to use, which model and which scale."""
    preset = PRESETS[opts.preset]
    out_w, out_h = target_size(info, opts.resolution)
    needed = max(out_w / info.width, out_h / info.height)
    realesrgan = find_realesrgan() if opts.use_ai is not False else None
    # Standard skips AI when there is almost nothing to upscale; Pro always reconstructs.
    if realesrgan and opts.use_ai is None and opts.engine == "standard" and needed < 1.2:
        realesrgan = None
    # Standard = fast video model; Pro = preset's model (x4plus is the most detailed for real footage).
    model = "realesr-animevideov3" if opts.engine == "standard" else preset.get("ai_model", "realesr-animevideov3")
    if model == "realesrgan-x4plus":
        scale = 4
    else:
        scale = 2 if needed <= 2 else (3 if needed <= 3 else 4)
    rife = find_rife() if target_fps(info, opts.fps) else None
    use_torch = opts.use_ai is not False and torch_engine_available()
    return {"realesrgan": realesrgan, "rife": rife, "model": model, "scale": scale, "torch": use_torch,
            "torch_model": torch_model_for(info, opts)}


def torch_model_for(info: VideoInfo, opts: EnhanceOptions) -> str:
    """Standard = fast compact model for real footage; Pro = full RRDB network (x2 when enough)."""
    out_w, out_h = target_size(info, opts.resolution)
    needed = max(out_w / info.width, out_h / info.height)
    if opts.engine == "standard":
        return "realesr-general-x4v3"
    return "RealESRGAN_x2plus" if needed <= 2 else "RealESRGAN_x4plus"


def _extract_frames(ffmpeg: str, input_path: Path, info: VideoInfo, opts: EnhanceOptions, rife: str,
                    tmp_dir: Path, report: ProgressFn, light: bool) -> tuple[Path, int, str]:
    """Decode to PNG frames and interpolate them with RIFE. Returns (frames_dir, count, rate)."""
    tfps = target_fps(info, opts.fps)
    frames = tmp_dir / "frames"
    frames.mkdir()
    vf = build_filters(info, opts, stage="pre", light=light, interpolate=False)
    cmd = [ffmpeg, "-y", "-hide_banner", "-i", str(input_path), "-map", "0:v:0", "-vf", vf,
           "-fps_mode", "cfr", "-r", info.rate, "-pix_fmt", "rgb24", "-compression_level", "1",
           str(frames / "%08d.png")]
    _run_ffmpeg(cmd, info.duration, report, 0.0, 0.08, "extracting frames")
    n = sum(1 for _ in frames.iterdir())
    if n == 0:
        raise EnhanceError("No frames could be decoded from the video.")
    target_n = max(n + 1, round(n * tfps / info.fps))
    rife_out = tmp_dir / "rife"
    rife_out.mkdir()
    _run_gpu_tool([rife, "-i", str(frames), "-o", str(rife_out), "-n", str(target_n),
                   "-m", str(Path(rife).parent / "rife-v4.6"), "-j", "2:2:2", "-f", "%08d.png"],
                  rife_out, target_n, report, 0.08, 0.07, "interpolating", "RIFE")
    shutil.rmtree(frames)
    return rife_out, target_n, f"{tfps:g}"


def _enhance_torch(ffmpeg: str, input_path: Path, output_path: Path, info: VideoInfo,
                   opts: EnhanceOptions, plan: dict, report: ProgressFn) -> None:
    from . import ai_engine
    from .bootstrap import bin_dir, face_weights_dir, model_path

    preset, engine_cfg = PRESETS[opts.preset], ENGINES[opts.engine]
    out_w, out_h = target_size(info, opts.resolution)
    report(0.0, "loading AI models")
    engine = ai_engine.Engine(
        model_path(plan["torch_model"]), plan["torch_model"],
        model_path("codeformer") if opts.faces else None, face_weights_dir(),
        in_size=(info.width, info.height), out_size=(out_w, out_h),
        post={
            # The AI model already restores detail, so sharpening stays light.
            "sharpen": min(1.0, preset["sharpen"] * engine_cfg["sharpen_mul"] * 0.5),
            "color": preset["color"],
            "temporal": 0.55 if preset.get("deflicker") else 0.4,
        },
        fidelity=preset.get("face_fidelity", 0.7),
        # Whole frame on small inputs; tiles on big ones so 8 GB cards never run out of memory.
        tile=0 if info.width * info.height <= 1280 * 720 else 512,
        trt_cache=bin_dir() / "trt",
        report=lambda label: report(0.0, label),
    )
    w, h = info.width, info.height
    tfps = target_fps(info, opts.fps)
    hwdec = ["-hwaccel", "cuda"] if nvenc_available() else []  # NVDEC: decode on the GPU too

    with tempfile.TemporaryDirectory(prefix="enhancer_") as tmp:
        tmp_dir = Path(tmp)
        start = 0.0
        if tfps and plan["rife"]:
            frames, total, rate = _extract_frames(ffmpeg, input_path, info, opts, plan["rife"], tmp_dir,
                                                  report, light=True)
            src = [ffmpeg, "-hide_banner", "-loglevel", "error", "-framerate", rate,
                   "-i", str(frames / "%08d.png")]
            start = 0.15
        else:
            rate = f"{tfps:g}" if tfps else info.rate  # FPS boost without RIFE: minterpolate in "pre"
            total = max(1, round(info.duration * _rate_value(rate)))
            src = [ffmpeg, "-hide_banner", "-loglevel", "error", *hwdec, "-i", str(input_path), "-map", "0:v:0",
                   "-vf", build_filters(info, opts, stage="pre", light=True, interpolate=bool(tfps)),
                   "-fps_mode", "cfr", "-r", rate]
        reader = subprocess.Popen([*src, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  creationflags=NO_WINDOW | LOW_PRIORITY)

        # Frames arrive finished (YUV 4:2:0 BT.709) - FFmpeg only encodes (NVENC) and adds the audio.
        enc = encoder_args(opts, nvenc=nvenc_available())
        writer = subprocess.Popen(
            [ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
             "-f", "rawvideo", "-pix_fmt", "yuv420p", "-s", f"{out_w}x{out_h}", "-framerate", rate,
             "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
             "-i", "-", "-i", str(input_path), "-map", "0:v:0", "-map", "1:a?",
             *enc, "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
             "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", str(output_path)],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            creationflags=NO_WINDOW | LOW_PRIORITY)
        err_tail: dict[str, bytes] = {}
        drains = [threading.Thread(target=lambda p=p, k=k: err_tail.__setitem__(k, p.stderr.read()), daemon=True)
                  for k, p in (("decoder", reader), ("encoder", writer))]
        for t in drains:
            t.start()

        started = time.time()

        def on_frame(i: int) -> None:
            if i % 2 == 0 or i == total:
                fps_now = i / max(1e-6, time.time() - started)
                report(start + (0.98 - start) * min(1.0, i / total),
                       f"AI enhancing {i}/{total} ({fps_now:.1f} fps, {engine.backend})")

        try:
            ai_engine.run_stream(engine, reader, writer, w, h, total, on_frame)
        finally:
            reader.wait()
            writer.wait()
            for t in drains:
                t.join(timeout=5)
        if writer.returncode != 0 or reader.returncode != 0:
            msg = (err_tail.get("encoder") or err_tail.get("decoder") or b"").decode("utf-8", "replace")
            raise EnhanceError("Encoding failed:\n" + msg[-1500:])


def _enhance_gpu(ffmpeg: str, input_path: Path, output_path: Path, info: VideoInfo,
                 opts: EnhanceOptions, plan: dict, report: ProgressFn) -> None:
    realesrgan, rife = plan["realesrgan"], plan["rife"]
    tfps = target_fps(info, opts.fps)
    rate = info.rate

    with tempfile.TemporaryDirectory(prefix="enhancer_") as tmp:
        tmp_dir = Path(tmp)
        frames = tmp_dir / "frames"
        frames.mkdir()

        # 1) Decode + cleanup, constant frame rate (phones record VFR) so audio stays in sync.
        # Without RIFE, FFmpeg's minterpolate does the FPS boost here.
        if tfps and not rife:
            rate = f"{tfps:g}"
        vf = build_filters(info, opts, stage="pre", light=bool(realesrgan), interpolate=not rife)
        cmd = [ffmpeg, "-y", "-hide_banner", "-i", str(input_path), "-map", "0:v:0", "-vf", vf,
               "-fps_mode", "cfr", "-r", rate, "-pix_fmt", "rgb24", "-compression_level", "1",
               str(frames / "%08d.png")]
        _run_ffmpeg(cmd, info.duration, report, 0.0, 0.10, "extracting frames")
        n = sum(1 for _ in frames.iterdir())
        if n == 0:
            raise EnhanceError("No frames could be decoded from the video.")

        # 2) RIFE frame interpolation on the GPU (before upscaling: small frames = fast).
        if rife and tfps:
            target_n = max(n + 1, round(n * tfps / info.fps))
            rife_out = tmp_dir / "rife"
            rife_out.mkdir()
            _run_gpu_tool([rife, "-i", str(frames), "-o", str(rife_out), "-n", str(target_n),
                           "-m", str(Path(rife).parent / "rife-v4.6"), "-j", "2:2:2", "-f", "%08d.png"],
                          rife_out, target_n, report, 0.10, 0.15, "interpolating", "RIFE")
            shutil.rmtree(frames)
            frames, n, rate = rife_out, target_n, f"{tfps:g}"

        # 3) Upscale + encode in chunks.
        names = sorted(p.name for p in frames.iterdir())
        segments: list[Path] = []
        start, span = (0.25, 0.70) if rife else (0.10, 0.85)
        chunk_size = CHUNK_FRAMES if realesrgan else len(names)
        for ci, first in enumerate(range(0, len(names), chunk_size)):
            batch = names[first:first + chunk_size]
            cin, cout = tmp_dir / f"c{ci}_in", tmp_dir / f"c{ci}_out"
            cin.mkdir()
            for j, name in enumerate(batch):  # renumber so each chunk starts at 1
                (frames / name).rename(cin / f"{j + 1:08d}.png")
            c_start = start + span * first / len(names)
            c_span = span * len(batch) / len(names)
            src_dir = cin
            if realesrgan:
                cout.mkdir()
                _run_gpu_tool([realesrgan, "-i", str(cin), "-o", str(cout), "-n", plan["model"],
                               "-m", str(Path(realesrgan).parent / "models"), "-s", str(plan["scale"]),
                               "-j", "2:2:2", "-f", "png"],
                              cout, len(batch), report, c_start, c_span * 0.8, "AI upscaling", "Real-ESRGAN",
                              offset=first, grand_total=len(names))
                shutil.rmtree(cin)
                src_dir = cout
            seg = tmp_dir / f"seg{ci:04d}.mp4"

            def build(enc: list[str], src_dir=src_dir, seg=seg) -> list[str]:
                return [ffmpeg, "-y", "-hide_banner", "-framerate", rate, "-i", str(src_dir / "%08d.png"),
                        "-vf", build_filters(info, opts, stage="post", light=bool(realesrgan)),
                        *enc, "-an", str(seg)]
            enc_start = c_start + (c_span * 0.8 if realesrgan else 0)
            enc_span = c_span * (0.2 if realesrgan else 1.0)
            _run_encode(build, opts, len(batch) / _rate_value(rate), report, enc_start, enc_span, "encoding")
            shutil.rmtree(src_dir)
            segments.append(seg)

        # 4) Join chunks + original audio.
        report(0.96, "finalizing")
        listing = tmp_dir / "segments.txt"
        listing.write_text("".join("file '" + s.as_posix().replace("'", "'\\''") + "'\n" for s in segments),
                           encoding="utf-8")
        cmd = [ffmpeg, "-y", "-hide_banner", "-f", "concat", "-safe", "0", "-i", str(listing),
               "-i", str(input_path), "-map", "0:v:0", "-map", "1:a?", "-c:v", "copy",
               "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", str(output_path)]
        _run_ffmpeg(cmd, info.duration, report, 0.96, 0.04, "finalizing")


def _rate_value(rate: str) -> float:
    if "/" in rate:
        num, den = rate.split("/")
        return float(num) / float(den)
    return float(rate)


def system_check() -> dict:
    status = {"ffmpeg": None, "ffprobe": None, "realesrgan": find_realesrgan(), "rife": find_rife(),
              "nvenc": nvenc_available(), "torch": torch_engine_available(), "ok": False}
    try:
        status["ffmpeg"], status["ffprobe"] = find_ffmpeg()
        status["ok"] = True
    except EnhanceError as e:
        status["error"] = str(e)
    return status
