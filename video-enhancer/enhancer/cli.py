"""Command line interface.

Windows only. Normally started by double-clicking run.bat.

    python -m enhancer                       # start the web UI (default)
    python -m enhancer serve --port 7860
    python -m enhancer enhance in.mp4 -r 4k -e pro -f 60 -p ugc
    python -m enhancer check
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from . import APP_NAME, __version__
from .pipeline import EnhanceError, EnhanceOptions, enhance, probe, system_check, target_size
from .presets import ENGINES, FPS_OPTIONS, PRESETS, RESOLUTIONS


def _progress_bar():
    started = time.time()

    def show(frac: float, label: str) -> None:
        width = 32
        filled = int(width * frac)
        elapsed = time.time() - started
        eta = (elapsed / frac - elapsed) if frac > 0.01 else 0
        bar = "█" * filled + "░" * (width - filled)
        sys.stdout.write(f"\r  {bar} {frac * 100:5.1f}%  {label:<24} ETA {int(eta // 60):02d}:{int(eta % 60):02d} ")
        sys.stdout.flush()

    return show


def cmd_enhance(args: argparse.Namespace) -> int:
    src = Path(args.input)
    out = Path(args.output) if args.output else src.with_name(f"{src.stem}_enhanced_{args.resolution}.mp4")
    opts = EnhanceOptions(engine=args.engine, resolution=args.resolution, fps=args.fps,
                          preset=args.preset, crf=args.crf,
                          use_ai=True if args.ai else (False if args.no_ai else None))
    try:
        info = probe(src)
        w, h = target_size(info, args.resolution)
        print(f"\n  {APP_NAME}")
        print(f"  Input : {src.name}  {info.width}x{info.height} @ {info.fps:.2f}fps, {info.duration:.1f}s")
        print(f"  Output: {out.name}  {w}x{h}  engine={args.engine} preset={args.preset} fps={args.fps}\n")
        enhance(src, out, opts, _progress_bar())
    except EnhanceError as e:
        print(f"\n  Error: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n  Cancelled.")
        return 130
    print(f"\n\n  Done -> {out.resolve()}\n")
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    from .server import serve
    serve(host=args.host, port=args.port, open_browser=not args.no_browser)
    return 0


def cmd_setup(args: argparse.Namespace) -> int:
    from .bootstrap import ensure_dependencies
    ensure_dependencies(force=args.force)
    return cmd_check(args)


def cmd_check(_: argparse.Namespace) -> int:
    status = system_check()
    print(f"{APP_NAME} v{__version__}")
    print(f"  ffmpeg     : {status['ffmpeg'] or 'NOT FOUND'}")
    print(f"  ffprobe    : {status['ffprobe'] or 'NOT FOUND'}")
    print(f"  Real-ESRGAN: {status['realesrgan'] or 'unavailable (no Vulkan GPU) - using FFmpeg filters'}")
    print(f"  RIFE       : {status['rife'] or 'unavailable - using FFmpeg interpolation'}")
    print(f"  NVENC      : {'enabled (NVIDIA GPU encoding)' if status['nvenc'] else 'unavailable - using CPU encoder (x264)'}")
    if not status["ok"]:
        print(f"\n  {status.get('error')}")
    return 0 if status["ok"] else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="enhancer", description=f"{APP_NAME} v{__version__}")
    parser.add_argument("--version", action="version", version=__version__)
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("enhance", help="Enhance a video from the command line")
    p.add_argument("input", help="Input video (MP4 / MOV / WEBM)")
    p.add_argument("-o", "--output", help="Output .mp4 path")
    p.add_argument("-e", "--engine", choices=ENGINES, default="standard", help="standard (fast) or pro (detail)")
    p.add_argument("-r", "--resolution", choices=RESOLUTIONS, default="1080p")
    p.add_argument("-f", "--fps", choices=FPS_OPTIONS, default="original", help="Frame interpolation target")
    p.add_argument("-p", "--preset", choices=PRESETS, default="ugc", help="ai | old_film | ugc | none")
    p.add_argument("--crf", type=int, help="x264 quality (lower = better, default 18/16)")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--ai", action="store_true", help="Force Real-ESRGAN upscaling")
    g.add_argument("--no-ai", action="store_true", help="Never use Real-ESRGAN")
    p.set_defaults(func=cmd_enhance)

    s = sub.add_parser("serve", help="Start the web interface")
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=7860)
    s.add_argument("--no-browser", action="store_true")
    s.set_defaults(func=cmd_serve)

    st = sub.add_parser("setup", help="Download FFmpeg and Real-ESRGAN (runs automatically on first launch)")
    st.add_argument("--force", action="store_true", help="Re-run setup even if already done")
    st.set_defaults(func=cmd_setup)

    c = sub.add_parser("check", help="Check that FFmpeg / Real-ESRGAN are available")
    c.set_defaults(func=cmd_check)
    return parser


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    if sys.platform != "win32" and not os.environ.get("ENHANCER_DEV"):
        print(f"{APP_NAME} supports Windows only.", file=sys.stderr)
        return 1
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        args = parser.parse_args(["serve"])
    if args.command in ("serve", "enhance"):
        from .bootstrap import ensure_dependencies
        try:
            ensure_dependencies()
        except Exception as e:  # noqa: BLE001
            print(f"\n  Setup failed: {e}\n  Check your internet connection and run again.", file=sys.stderr)
            return 1
    return args.func(args)
