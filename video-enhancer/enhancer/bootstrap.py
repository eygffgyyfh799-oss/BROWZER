"""First-run setup: download FFmpeg and Real-ESRGAN automatically.

Everything is installed into ``video-enhancer/bin`` (or ``~/.video-enhancer/bin``
when the tool folder is read-only), so nothing is installed system wide.
"""

from __future__ import annotations

import json
import os
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent.parent

FFMPEG_URLS = {
    "windows": "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip",
    "linux": "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz",
    "linux-arm": "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linuxarm64-gpl.tar.xz",
}
FFMPEG_MAC = ["https://evermeet.cx/ffmpeg/getrelease/zip", "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip"]

_RE = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-{}.zip"
REALESRGAN_URLS = {"windows": _RE.format("windows"), "linux": _RE.format("ubuntu"), "mac": _RE.format("macos")}

_RIFE = "https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-{}.zip"
RIFE_URLS = {"windows": _RIFE.format("windows"), "linux": _RIFE.format("ubuntu"), "mac": _RIFE.format("macos")}
RIFE_MODEL = "rife-v4.6"


def _os() -> str:
    s = platform.system().lower()
    if s.startswith("win"):
        return "windows"
    if s == "darwin":
        return "mac"
    if platform.machine().lower() in ("aarch64", "arm64"):
        return "linux-arm"
    return "linux"


def _exe(name: str) -> str:
    return name + (".exe" if _os() == "windows" else "")


def bin_dir() -> Path:
    preferred = TOOL_DIR / "bin"
    try:
        preferred.mkdir(parents=True, exist_ok=True)
        probe = preferred / ".write_test"
        probe.write_text("ok")
        probe.unlink()
        return preferred
    except OSError:
        fallback = Path.home() / ".video-enhancer" / "bin"
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


def _state_path() -> Path:
    return bin_dir() / "state.json"


def load_state() -> dict:
    try:
        return json.loads(_state_path().read_text())
    except (OSError, ValueError):
        return {}


def save_state(**fields) -> None:
    state = load_state()
    state.update(fields)
    _state_path().write_text(json.dumps(state, indent=2))


# --------------------------------------------------------------------------- locating

def local_ffmpeg() -> tuple[str, str] | None:
    d = bin_dir() / "ffmpeg"
    ff, fp = d / _exe("ffmpeg"), d / _exe("ffprobe")
    if ff.exists() and fp.exists():
        return str(ff), str(fp)
    return None


def local_realesrgan() -> str | None:
    for d in (bin_dir() / "realesrgan", bin_dir()):
        exe = d / _exe("realesrgan-ncnn-vulkan")
        if exe.exists():
            return str(exe)
    return None


def local_rife() -> str | None:
    exe = bin_dir() / "rife" / _exe("rife-ncnn-vulkan")
    return str(exe) if exe.exists() and (exe.parent / RIFE_MODEL).is_dir() else None


# --------------------------------------------------------------------------- download helpers

def _download(url: str, dest: Path, label: str) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "video-enhancer"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r, dest.open("wb") as f:
                total = int(r.headers.get("Content-Length") or 0)
                done = 0
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    done += len(chunk)
                    if total:
                        pct = done / total
                        bar = "█" * int(pct * 30) + "░" * (30 - int(pct * 30))
                        sys.stdout.write(f"\r    {label}: {bar} {pct * 100:5.1f}%  {done / 1048576:.0f}/{total / 1048576:.0f} MB ")
                    else:
                        sys.stdout.write(f"\r    {label}: {done / 1048576:.0f} MB ")
                    sys.stdout.flush()
            print()
            return
        except OSError as e:
            if attempt == 3:
                raise RuntimeError(f"Download failed ({url}): {e}") from e
            print(f"\n    retrying ({e})...")
            time.sleep(2 ** (attempt + 1))


def _extract(archive: Path, dest: Path) -> None:
    if archive.name.endswith(".zip") or zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            z.extractall(dest)
    else:
        with tarfile.open(archive) as t:
            t.extractall(dest)


def _make_executable(path: Path) -> None:
    if _os() != "windows":
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        if _os() == "mac":  # remove Gatekeeper quarantine so it can run
            subprocess.run(["xattr", "-dr", "com.apple.quarantine", str(path)], capture_output=True)


# --------------------------------------------------------------------------- installers

def install_ffmpeg() -> tuple[str, str]:
    target = bin_dir() / "ffmpeg"
    target.mkdir(parents=True, exist_ok=True)
    print("  • Installing FFmpeg ...")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        if _os() == "mac":
            if shutil.which("brew"):
                subprocess.run(["brew", "install", "ffmpeg"], check=False)
                ff, fp = shutil.which("ffmpeg"), shutil.which("ffprobe")
                if ff and fp:
                    return ff, fp
            for i, url in enumerate(FFMPEG_MAC):
                arc = tmp / f"{i}.zip"
                _download(url, arc, ["ffmpeg", "ffprobe"][i])
                _extract(arc, tmp / "x")
        else:
            url = FFMPEG_URLS[_os()]
            arc = tmp / url.rsplit("/", 1)[1]
            _download(url, arc, "FFmpeg")
            print("    extracting ...")
            _extract(arc, tmp / "x")
        for name in ("ffmpeg", "ffprobe"):
            found = next((p for p in (tmp / "x").rglob(_exe(name)) if p.is_file()), None)
            if not found:
                raise RuntimeError(f"{name} not found in downloaded archive")
            shutil.copy2(found, target / _exe(name))
            _make_executable(target / _exe(name))
    result = local_ffmpeg()
    assert result
    print("    FFmpeg ready.")
    return result


def install_realesrgan() -> str | None:
    key = "linux" if _os() == "linux-arm" else _os()
    if _os() == "linux-arm":
        print("  • Real-ESRGAN has no ARM Linux build; Pro engine will use FFmpeg filters.")
        return None
    target = bin_dir() / "realesrgan"
    print("  • Installing Real-ESRGAN (AI upscaling models) ...")
    with tempfile.TemporaryDirectory() as tmp:
        arc = Path(tmp) / "realesrgan.zip"
        _download(REALESRGAN_URLS[key], arc, "Real-ESRGAN")
        print("    extracting ...")
        if target.exists():
            shutil.rmtree(target)
        _extract(arc, target)
    for sub in target.iterdir():  # flatten if the zip had a top-level folder
        if sub.is_dir() and (sub / _exe("realesrgan-ncnn-vulkan")).exists():
            for item in sub.iterdir():
                shutil.move(str(item), target / item.name)
            sub.rmdir()
    for junk in ("onepiece_demo.mp4", "input2.jpg"):
        (target / junk).unlink(missing_ok=True)
    exe = target / _exe("realesrgan-ncnn-vulkan")
    if not exe.exists():
        raise RuntimeError("realesrgan-ncnn-vulkan not found in downloaded archive")
    _make_executable(exe)
    return str(exe)


def test_realesrgan(exe: str) -> bool:
    """Run the model once on the bundled sample image to confirm the GPU (Vulkan) works."""
    sample = Path(exe).parent / "input.jpg"
    if not sample.exists():
        return True
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "out.png"
        try:
            r = subprocess.run([exe, "-i", str(sample), "-o", str(out), "-n", "realesr-animevideov3", "-s", "2"],
                               capture_output=True, timeout=180, cwd=str(Path(exe).parent))
        except (OSError, subprocess.TimeoutExpired):
            return False
        return r.returncode == 0 and out.exists() and out.stat().st_size > 0


def install_rife() -> str | None:
    if _os() == "linux-arm":
        return None
    target = bin_dir() / "rife"
    print("  • Installing RIFE (GPU frame interpolation for 30/60fps) ...")
    with tempfile.TemporaryDirectory() as tmp:
        arc = Path(tmp) / "rife.zip"
        _download(RIFE_URLS[_os()], arc, "RIFE")
        print("    extracting ...")
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True)
        with zipfile.ZipFile(arc) as z:  # keep only the program and the one model we use
            for member in z.infolist():
                parts = Path(member.filename).parts
                rel = Path(*parts[1:]) if len(parts) > 1 else Path(parts[0])
                keep = rel.parts and (rel.parts[0] == RIFE_MODEL or (len(rel.parts) == 1 and
                                      rel.suffix.lower() in ("", ".exe", ".dll", ".dylib")))
                if not keep or member.is_dir():
                    continue
                dest = target / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                with z.open(member) as src, dest.open("wb") as out:
                    shutil.copyfileobj(src, out)
    exe = target / _exe("rife-ncnn-vulkan")
    if not exe.exists():
        raise RuntimeError("rife-ncnn-vulkan not found in downloaded archive")
    _make_executable(exe)
    return str(exe)


def test_rife(exe: str, ffmpeg: str) -> bool:
    with tempfile.TemporaryDirectory() as tmp:
        src, out = Path(tmp) / "in", Path(tmp) / "out"
        src.mkdir()
        out.mkdir()
        subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=256x144:rate=10:duration=0.3",
                        str(src / "%08d.png")], capture_output=True)
        try:
            r = subprocess.run([exe, "-i", str(src), "-o", str(out), "-n", "6",
                                "-m", str(Path(exe).parent / RIFE_MODEL)],
                               capture_output=True, timeout=180, cwd=str(Path(exe).parent))
        except (OSError, subprocess.TimeoutExpired):
            return False
        return r.returncode == 0 and len(list(out.glob("*.png"))) == 6


def test_nvenc(ffmpeg: str) -> bool:
    """NVIDIA hardware encoder (needs an NVIDIA GPU and a recent driver)."""
    try:
        r = subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30:duration=0.5",
                            "-c:v", "h264_nvenc", "-preset", "p6", "-tune", "hq", "-rc", "vbr", "-cq", "19",
                            "-b:v", "0", "-spatial-aq", "1", "-temporal-aq", "1", "-f", "null", "-"],
                           capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0


# --------------------------------------------------------------------------- entry point

def ensure_dependencies(force: bool = False, quiet: bool = False) -> dict:
    """Install whatever is missing. Safe to call on every launch."""
    from .pipeline import EnhanceError, find_ffmpeg

    state = load_state()
    first = not state.get("setup_done") or force
    pending = first or not state.get("rife_checked") or "nvenc_ok" not in state
    if pending and not quiet:
        print("\n  Setup — downloading / checking required components (one time only)...\n")

    # FFmpeg (required)
    try:
        if force and not local_ffmpeg():
            raise EnhanceError("reinstall")
        find_ffmpeg()
    except EnhanceError:
        install_ffmpeg()

    # Real-ESRGAN (optional; only tried once unless forced)
    if first or not state.get("ai_checked"):
        exe = local_realesrgan()
        if not exe:
            try:
                exe = install_realesrgan()
            except Exception as e:  # noqa: BLE001 - optional component
                print(f"    Real-ESRGAN could not be installed: {e}")
                exe = None
        ok = bool(exe) and test_realesrgan(exe)
        if exe and not ok:
            print("    Real-ESRGAN needs a Vulkan-capable GPU — not available on this machine.\n"
                  "    The Pro engine will use advanced FFmpeg filters instead.")
        elif ok:
            print("    Real-ESRGAN ready (GPU AI upscaling enabled).")
        save_state(ai_checked=True, ai_ok=ok)

    ffmpeg = find_ffmpeg()[0]

    # NVIDIA hardware encoding.
    if first or "nvenc_ok" not in state:
        ok = test_nvenc(ffmpeg)
        print(f"    NVENC (NVIDIA GPU encoding): {'enabled' if ok else 'not available - using CPU encoder'}")
        save_state(nvenc_ok=ok)

    # RIFE GPU frame interpolation.
    if first or not state.get("rife_checked"):
        exe = local_rife()
        if not exe:
            try:
                exe = install_rife()
            except Exception as e:  # noqa: BLE001 - optional component
                print(f"    RIFE could not be installed: {e}")
                exe = None
        ok = bool(exe) and test_rife(exe, ffmpeg)
        print(f"    RIFE (GPU 30/60fps): {'enabled' if ok else 'not available - using FFmpeg interpolation'}")
        save_state(rife_checked=True, rife_ok=ok)

    save_state(setup_done=True)
    if pending and not quiet:
        print("\n  Setup complete.\n")
    return load_state()

