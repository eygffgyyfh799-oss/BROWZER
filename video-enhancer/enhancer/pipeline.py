"""Video enhancement pipeline.

Two processing paths:

* FFmpeg path (always available): temporal denoise, deblocking, Lanczos
  upscaling, contrast-adaptive sharpening, color correction and motion
  compensated frame interpolation, all in a single FFmpeg filter graph.
* AI path (Pro engine, when ``realesrgan-ncnn-vulkan`` is installed): the
  cleaned frames are upscaled frame by frame with Real-ESRGAN, then
  re-assembled with a deflicker pass for temporal consistency.
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

from .presets import ENGINES, FPS_OPTIONS, PRESETS, RESOLUTIONS

ProgressFn = Callable[[float, str], None]

SUPPORTED_EXTENSIONS = {".mp4", ".mov", ".webm", ".mkv", ".avi", ".m4v"}


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


@dataclass
class EnhanceOptions:
    engine: str = "standard"        # standard | pro
    resolution: str = "1080p"       # 1080p | 4k
    fps: str = "original"           # original | 30 | 60
    preset: str = "ugc"             # ai | old_film | ugc | none
    use_ai: Optional[bool] = None   # None = auto (pro engine + binary found)
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
    ffmpeg = os.environ.get("FFMPEG_PATH") or shutil.which("ffmpeg")
    ffprobe = os.environ.get("FFPROBE_PATH") or shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise EnhanceError(
            "FFmpeg was not found. Install it (https://ffmpeg.org/download.html) "
            "and make sure 'ffmpeg' and 'ffprobe' are on your PATH."
        )
    return ffmpeg, ffprobe


def find_realesrgan() -> Optional[str]:
    path = os.environ.get("REALESRGAN_PATH")
    if path and Path(path).exists():
        return path
    for name in ("realesrgan-ncnn-vulkan", "realesrgan-ncnn-vulkan.exe"):
        found = shutil.which(name)
        if found:
            return found
    local = Path(__file__).resolve().parent.parent / "bin"
    for name in ("realesrgan-ncnn-vulkan", "realesrgan-ncnn-vulkan.exe"):
        if (local / name).exists():
            return str(local / name)
    return None


def probe(path: str | Path) -> VideoInfo:
    _, ffprobe = find_ffmpeg()
    cmd = [ffprobe, "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)]
    result = subprocess.run(cmd, capture_output=True, text=True)
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

    fps = parse_rate(video.get("avg_frame_rate", "0/0")) or parse_rate(video.get("r_frame_rate", "0/0")) or 30.0
    duration = float(video.get("duration") or data.get("format", {}).get("duration") or 0)
    width, height = int(video["width"]), int(video["height"])
    rotation = _rotation(video)
    if rotation in (90, 270):
        width, height = height, width
    return VideoInfo(width, height, fps, duration, has_audio, int(duration * fps))


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


def build_filters(info: VideoInfo, opts: EnhanceOptions, *, stage: str = "full") -> str:
    """Build the FFmpeg filter graph.

    stage = "full"  : everything (FFmpeg-only path)
    stage = "pre"   : cleanup + interpolation before AI upscaling
    stage = "post"  : scaling to target + sharpen/color/deflicker after AI upscaling
    """
    preset = PRESETS[opts.preset]
    engine = ENGINES[opts.engine]
    out_w, out_h = target_size(info, opts.resolution)
    fps = target_fps(info, opts.fps)
    chain: list[str] = []

    if stage in ("full", "pre"):
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
        chain.append(f"hqdn3d={luma_s}:{chroma_s}:{luma_t}:{chroma_t}")
        if engine["nlmeans"] and preset.get("nlmeans"):
            chain.append(f"nlmeans=s={preset['nlmeans']}:p=7:r=9")
        if engine["temporal_denoise"]:
            chain.append("atadenoise=0a=0.02:0b=0.04:1a=0.02:1b=0.04:2a=0.02:2b=0.04:s=9")
        # Frame interpolation on the small frames (much cheaper than after upscaling).
        if fps:
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
        chain.append(f"cas=strength={min(1.0, preset['sharpen'] * engine['sharpen_mul']):.2f}")
        if engine["edge_unsharp"]:
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

    chain.append("format=yuv420p")
    return ",".join(chain)


def encoder_args(opts: EnhanceOptions) -> list[str]:
    engine = ENGINES[opts.engine]
    crf = opts.crf if opts.crf is not None else engine["crf"]
    return [
        "-c:v", "libx264", "-preset", engine["x264_preset"], "-crf", str(crf),
        "-tune", "film", "-profile:v", "high", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
    ]


# --------------------------------------------------------------------------- running

def _run_ffmpeg(cmd: list[str], duration: float, progress: Optional[ProgressFn],
                start: float, span: float, label: str) -> None:
    proc = subprocess.Popen(
        [cmd[0], "-nostdin", *cmd[1:], "-progress", "pipe:1", "-nostats"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
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

    realesrgan = find_realesrgan()
    use_ai = opts.use_ai if opts.use_ai is not None else (opts.engine == "pro" and realesrgan is not None)
    if use_ai and not realesrgan:
        raise EnhanceError(
            "AI upscaling requested but 'realesrgan-ncnn-vulkan' was not found. "
            "Download it from https://github.com/xinntao/Real-ESRGAN/releases and put it on PATH, "
            "in video-enhancer/bin, or set REALESRGAN_PATH."
        )

    if use_ai:
        _enhance_ai(ffmpeg, realesrgan, input_path, output_path, info, opts, report)
    else:
        cmd = [ffmpeg, "-y", "-hide_banner", "-i", str(input_path),
               "-map", "0:v:0", "-map", "0:a?", "-vf", build_filters(info, opts),
               *encoder_args(opts), "-c:a", "aac", "-b:a", "192k", str(output_path)]
        _run_ffmpeg(cmd, info.duration, report, 0.02, 0.98, "enhancing")

    report(1.0, "done")
    return output_path


def _enhance_ai(ffmpeg: str, realesrgan: str, input_path: Path, output_path: Path,
                info: VideoInfo, opts: EnhanceOptions, report: ProgressFn) -> None:
    preset = PRESETS[opts.preset]
    out_w, out_h = target_size(info, opts.resolution)
    scale = 4 if max(out_w / info.width, out_h / info.height) > 2.05 else 2
    model = preset.get("ai_model", "realesr-animevideov3")
    if model == "realesrgan-x4plus":
        scale = 4  # this model only supports x4
    fps = target_fps(info, opts.fps) or info.fps

    with tempfile.TemporaryDirectory(prefix="enhancer_") as tmp:
        tmp_dir = Path(tmp)
        frames_in, frames_out = tmp_dir / "in", tmp_dir / "out"
        frames_in.mkdir()
        frames_out.mkdir()

        # 1) Cleanup + interpolation, export frames.
        cmd = [ffmpeg, "-y", "-hide_banner", "-i", str(input_path), "-map", "0:v:0",
               "-vf", build_filters(info, opts, stage="pre").replace(",format=yuv420p", ""),
               "-fps_mode", "passthrough", str(frames_in / "%08d.png")]
        _run_ffmpeg(cmd, info.duration, report, 0.0, 0.15, "extracting frames")

        # 2) Real-ESRGAN, frame by frame.
        total = len(list(frames_in.glob("*.png"))) or 1
        proc = subprocess.Popen(
            [realesrgan, "-i", str(frames_in), "-o", str(frames_out), "-n", model,
             "-s", str(scale), "-f", "png"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        )
        while proc.poll() is None:
            done = len(list(frames_out.glob("*.png")))
            report(0.15 + 0.65 * done / total, f"AI upscaling {done}/{total}")
            time.sleep(1.0)
        if proc.returncode != 0:
            err = proc.stderr.read() if proc.stderr else ""
            raise EnhanceError(f"Real-ESRGAN failed:\n{err[-1500:]}")

        # 3) Re-assemble with audio, final scaling, deflicker, color.
        cmd = [ffmpeg, "-y", "-hide_banner", "-framerate", f"{fps:g}",
               "-i", str(frames_out / "%08d.png"), "-i", str(input_path),
               "-map", "0:v:0", "-map", "1:a?", "-vf", build_filters(info, opts, stage="post"),
               *encoder_args(opts), "-c:a", "aac", "-b:a", "192k", "-shortest", str(output_path)]
        _run_ffmpeg(cmd, total / fps, report, 0.80, 0.20, "encoding")


def system_check() -> dict:
    status = {"ffmpeg": None, "ffprobe": None, "realesrgan": find_realesrgan(), "ok": False}
    try:
        status["ffmpeg"], status["ffprobe"] = find_ffmpeg()
        status["ok"] = True
    except EnhanceError as e:
        status["error"] = str(e)
    return status
