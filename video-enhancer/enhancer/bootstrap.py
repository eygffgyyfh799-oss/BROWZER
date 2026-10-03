"""First-run setup (Windows): download FFmpeg, Real-ESRGAN and RIFE automatically.

Everything is installed into the tool's ``bin`` folder (or
``%LOCALAPPDATA%\\AI Video Enhancer\\bin`` when the tool folder is read-only),
so nothing is installed system wide.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent.parent
APP_DATA = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local") / "AI Video Enhancer"

FFMPEG_URL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
REALESRGAN_URL = ("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/"
                  "realesrgan-ncnn-vulkan-20220424-windows.zip")
RIFE_URL = ("https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/"
            "rife-ncnn-vulkan-20221029-windows.zip")
RIFE_MODEL = "rife-v4.6"

# PyTorch AI engine (NVIDIA): models downloaded from their official GitHub releases.
AI_MODELS = {
    "realesr-general-x4v3": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth",
    "RealESRGAN_x4plus": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
    "RealESRGAN_x2plus": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth",
    "codeformer": "https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/codeformer.pth",
}
# Face detection / parsing weights used by facexlib (same file names facexlib looks for).
FACE_WEIGHTS = {
    "detection_Resnet50_Final.pth": "https://github.com/xinntao/facexlib/releases/download/v0.1.0/detection_Resnet50_Final.pth",
    "parsing_parsenet.pth": "https://github.com/xinntao/facexlib/releases/download/v0.2.2/parsing_parsenet.pth",
}
# CUDA builds of PyTorch, newest first (RTX 50 series needs CUDA 12.8 or newer).
TORCH_INDEXES = ["cu130", "cu129", "cu128"]
AI_PACKAGES = ["spandrel", "spandrel_extra_arches", "opencv-python-headless", "numpy", "scipy", "Pillow", "tqdm"]

# Hide the console window of helper processes started by the web server.
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def bin_dir() -> Path:
    preferred = TOOL_DIR / "bin"
    try:
        preferred.mkdir(parents=True, exist_ok=True)
        probe = preferred / ".write_test"
        probe.write_text("ok")
        probe.unlink()
        return preferred
    except OSError:
        fallback = APP_DATA / "bin"
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


def _state_path() -> Path:
    return bin_dir() / "state.json"


def load_state() -> dict:
    try:
        return json.loads(_state_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_state(**fields) -> None:
    state = load_state()
    state.update(fields)
    _state_path().write_text(json.dumps(state, indent=2), encoding="utf-8")


# --------------------------------------------------------------------------- locating

def local_ffmpeg() -> tuple[str, str] | None:
    d = bin_dir() / "ffmpeg"
    ff, fp = d / "ffmpeg.exe", d / "ffprobe.exe"
    if ff.exists() and fp.exists():
        return str(ff), str(fp)
    return None


def local_realesrgan() -> str | None:
    exe = bin_dir() / "realesrgan" / "realesrgan-ncnn-vulkan.exe"
    return str(exe) if exe.exists() else None


def local_rife() -> str | None:
    exe = bin_dir() / "rife" / "rife-ncnn-vulkan.exe"
    return str(exe) if exe.exists() and (exe.parent / RIFE_MODEL).is_dir() else None


def models_dir() -> Path:
    return Path(os.environ["ENHANCER_MODELS"]) if os.environ.get("ENHANCER_MODELS") else bin_dir() / "models"


def model_path(name: str) -> Path:
    return models_dir() / Path(AI_MODELS[name]).name


def face_weights_dir() -> Path:
    return models_dir() / "facexlib"


def ai_models_ready() -> bool:
    return (all(model_path(n).exists() for n in AI_MODELS)
            and all((face_weights_dir() / n).exists() for n in FACE_WEIGHTS))


def venv_python() -> Path:
    return bin_dir() / "venv" / "Scripts" / "python.exe"


# --------------------------------------------------------------------------- download helpers

def _download(url: str, dest: Path, label: str) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "ai-video-enhancer"})
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


def _extract_selected(archive: Path, target: Path, keep) -> None:
    """Extract members for which keep(relative_path) is true, dropping the archive's top folder."""
    with zipfile.ZipFile(archive) as z:
        names = [m.filename for m in z.infolist()]
        tops = {Path(n).parts[0] for n in names if Path(n).parts}
        strip = len(tops) == 1 and all(len(Path(n).parts) > 1 or n.endswith("/") for n in names)
        for member in z.infolist():
            if member.is_dir():
                continue
            parts = Path(member.filename).parts
            rel = Path(*parts[1:]) if strip else Path(*parts)
            if not keep(rel):
                continue
            dest = target / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(member) as src, dest.open("wb") as out:
                shutil.copyfileobj(src, out)


# --------------------------------------------------------------------------- installers

def install_ffmpeg() -> tuple[str, str]:
    target = bin_dir() / "ffmpeg"
    print("  • Installing FFmpeg ...")
    with tempfile.TemporaryDirectory() as tmp:
        arc = Path(tmp) / "ffmpeg.zip"
        _download(FFMPEG_URL, arc, "FFmpeg")
        print("    extracting ...")
        target.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(arc) as z:
            for member in z.infolist():
                name = Path(member.filename).name.lower()
                if name in ("ffmpeg.exe", "ffprobe.exe"):
                    with z.open(member) as src, (target / name).open("wb") as out:
                        shutil.copyfileobj(src, out)
    result = local_ffmpeg()
    if not result:
        raise RuntimeError("ffmpeg.exe not found in downloaded archive")
    print("    FFmpeg ready.")
    return result


def install_realesrgan() -> str:
    target = bin_dir() / "realesrgan"
    print("  • Installing Real-ESRGAN (AI upscaling models) ...")
    with tempfile.TemporaryDirectory() as tmp:
        arc = Path(tmp) / "realesrgan.zip"
        _download(REALESRGAN_URL, arc, "Real-ESRGAN")
        print("    extracting ...")
        if target.exists():
            shutil.rmtree(target)
        _extract_selected(arc, target, lambda rel: rel.suffix.lower() in (".exe", ".dll", ".bin", ".param")
                          or rel.name == "input.jpg")
    exe = local_realesrgan()
    if not exe:
        raise RuntimeError("realesrgan-ncnn-vulkan.exe not found in downloaded archive")
    return exe


def install_rife() -> str:
    target = bin_dir() / "rife"
    print("  • Installing RIFE (GPU frame interpolation for 30/60fps) ...")
    with tempfile.TemporaryDirectory() as tmp:
        arc = Path(tmp) / "rife.zip"
        _download(RIFE_URL, arc, "RIFE")
        print("    extracting ...")
        if target.exists():
            shutil.rmtree(target)
        # Keep only the program and the one model we use (the archive has ~400 MB of models).
        _extract_selected(arc, target, lambda rel: (rel.parts[0] == RIFE_MODEL) or
                          (len(rel.parts) == 1 and rel.suffix.lower() in (".exe", ".dll")))
    exe = local_rife()
    if not exe:
        raise RuntimeError("rife-ncnn-vulkan.exe not found in downloaded archive")
    return exe


def nvidia_gpus() -> list[str]:
    smi = shutil.which("nvidia-smi")
    if not smi:
        return []
    try:
        r = subprocess.run([smi, "--query-gpu=name", "--format=csv,noheader"], capture_output=True, text=True,
                           timeout=20, creationflags=NO_WINDOW)
    except (OSError, subprocess.TimeoutExpired):
        return []
    return [line.strip() for line in r.stdout.splitlines() if line.strip()] if r.returncode == 0 else []


_CUDA_TEST = ("import torch;assert torch.cuda.is_available();"
              "x=torch.randn(256,256,device='cuda',dtype=torch.half);float((x@x).float().mean());"
              "import torch.nn.functional as F;F.conv2d(x[None,None],torch.ones(1,1,3,3,device='cuda',dtype=torch.half));"
              "print(torch.__version__, torch.cuda.get_device_name(0))")


def install_ai_runtime() -> bool:
    """Create bin/venv with PyTorch (CUDA) + model libraries and download the AI models."""
    vpy = venv_python()
    print("  • Installing the PyTorch AI engine (CUDA) — about 4 GB, one time only ...")
    if not vpy.exists():
        subprocess.run([sys.executable, "-m", "venv", str(vpy.parent.parent)], check=True)
    pip = [str(vpy), "-m", "pip", "install", "--disable-pip-version-check", "--no-warn-script-location",
           "--progress-bar", "on"]
    subprocess.run(pip + ["--upgrade", "pip"], capture_output=True)

    ok = False
    for i, index in enumerate(TORCH_INDEXES):
        print(f"    PyTorch ({index}) ...")
        extra = ["--force-reinstall"] if i else []
        r = subprocess.run(pip + extra + ["torch", "torchvision", "--index-url", f"https://download.pytorch.org/whl/{index}"])
        if r.returncode != 0:
            continue
        test = subprocess.run([str(vpy), "-c", _CUDA_TEST], capture_output=True, text=True)
        if test.returncode == 0:
            print(f"    PyTorch works on the GPU: {test.stdout.strip()}")
            ok = True
            break
        print("    this build does not run on this GPU, trying the next one ...")
    if not ok:
        return False

    print("    Model libraries ...")
    if subprocess.run(pip + AI_PACKAGES).returncode != 0:
        return False
    # facexlib without its tracking extras (filterpy/numba fail to build on many PCs; we only need detection).
    if subprocess.run(pip + ["--no-deps", "facexlib"]).returncode != 0:
        return False

    print("    AI models (Real-ESRGAN, CodeFormer, face detection) ...")
    for name, url in AI_MODELS.items():
        dest = model_path(name)
        if not dest.exists():
            dest.parent.mkdir(parents=True, exist_ok=True)
            _download(url, dest.with_suffix(".part"), name)
            dest.with_suffix(".part").rename(dest)
    for name, url in FACE_WEIGHTS.items():
        dest = face_weights_dir() / name
        if not dest.exists():
            dest.parent.mkdir(parents=True, exist_ok=True)
            _download(url, dest.with_suffix(".part"), name)
            dest.with_suffix(".part").rename(dest)
    return True


# --------------------------------------------------------------------------- hardware tests

def _quiet_run(cmd: list[str], timeout: int = 180, cwd: str | None = None) -> bool:
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=timeout, cwd=cwd, creationflags=NO_WINDOW)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0


def test_realesrgan(exe: str) -> bool:
    """Run the model once on the bundled sample image to confirm the GPU (Vulkan) works."""
    sample = Path(exe).parent / "input.jpg"
    if not sample.exists():
        return True
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "out.png"
        ok = _quiet_run([exe, "-i", str(sample), "-o", str(out), "-n", "realesr-animevideov3", "-s", "2",
                         "-m", str(Path(exe).parent / "models")], cwd=str(Path(exe).parent))
        return ok and out.exists() and out.stat().st_size > 0


def test_rife(exe: str, ffmpeg: str) -> bool:
    with tempfile.TemporaryDirectory() as tmp:
        src, out = Path(tmp) / "in", Path(tmp) / "out"
        src.mkdir()
        out.mkdir()
        _quiet_run([ffmpeg, "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=256x144:rate=10:duration=0.3",
                    str(src / "%08d.png")])
        ok = _quiet_run([exe, "-i", str(src), "-o", str(out), "-n", "6", "-m", str(Path(exe).parent / RIFE_MODEL)],
                        cwd=str(Path(exe).parent))
        return ok and len(list(out.glob("*.png"))) == 6


def test_nvenc(ffmpeg: str) -> bool:
    """NVIDIA hardware encoder (needs an NVIDIA GPU and a recent driver)."""
    return _quiet_run([ffmpeg, "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30:duration=0.5",
                       "-c:v", "h264_nvenc", "-preset", "p6", "-tune", "hq", "-rc", "vbr", "-cq", "19",
                       "-b:v", "0", "-spatial-aq", "1", "-temporal-aq", "1", "-f", "null", "-"], timeout=60)


def gpu_name() -> str:
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-Command",
                            "(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join ', '"],
                           capture_output=True, text=True, timeout=20, creationflags=NO_WINDOW)
        return r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def create_desktop_shortcut() -> bool:
    """Put an 'AI Video Enhancer' shortcut on the desktop that starts run.bat."""
    def ps_quote(value: object) -> str:
        return "'" + str(value).replace("'", "''") + "'"

    script = (
        "$s=(New-Object -ComObject WScript.Shell);"
        "$d=[Environment]::GetFolderPath('Desktop');"
        "$l=$s.CreateShortcut((Join-Path $d 'AI Video Enhancer.lnk'));"
        f"$l.TargetPath={ps_quote(TOOL_DIR / 'run.bat')};"
        f"$l.WorkingDirectory={ps_quote(TOOL_DIR)};"
        "$l.Save()"
    )
    return _quiet_run(["powershell", "-NoProfile", "-Command", script], timeout=30)


# --------------------------------------------------------------------------- entry point

def _optional(installer, finder) -> str | None:
    exe = finder()
    if exe:
        return exe
    try:
        return installer()
    except Exception as e:  # noqa: BLE001 - optional component, the tool still works without it
        print(f"    could not be installed: {e}")
        return None


def ensure_dependencies(force: bool = False, quiet: bool = False) -> dict:
    """Install whatever is missing and test the GPU. Safe to call on every launch."""
    from .pipeline import EnhanceError, find_ffmpeg

    state = load_state()
    first = not state.get("setup_done") or force
    pending = first or not state.get("rife_checked") or "nvenc_ok" not in state or not state.get("torch_checked")
    if pending and not quiet:
        print("\n  Setup — downloading and checking required components (one time only)...\n")

    # FFmpeg (required)
    try:
        if force and not local_ffmpeg():
            raise EnhanceError("reinstall")
        ffmpeg = find_ffmpeg()[0]
    except EnhanceError:
        ffmpeg = install_ffmpeg()[0]

    if pending and not quiet:
        gpu = gpu_name()
        if gpu:
            print(f"    GPU detected: {gpu}")

    # Real-ESRGAN: AI upscaling on the GPU.
    if first or not state.get("ai_checked"):
        exe = _optional(install_realesrgan, local_realesrgan)
        ok = bool(exe) and test_realesrgan(exe)
        print(f"    Real-ESRGAN (GPU AI upscaling): {'enabled' if ok else 'not available - using FFmpeg filters'}")
        save_state(ai_checked=True, ai_ok=ok)

    # NVIDIA hardware encoding.
    if first or "nvenc_ok" not in state:
        ok = test_nvenc(ffmpeg)
        print(f"    NVENC (NVIDIA GPU encoding):    {'enabled' if ok else 'not available - using CPU encoder'}")
        save_state(nvenc_ok=ok)

    # RIFE: frame interpolation on the GPU.
    if first or not state.get("rife_checked"):
        exe = _optional(install_rife, local_rife)
        ok = bool(exe) and test_rife(exe, ffmpeg)
        print(f"    RIFE (GPU 30/60fps):            {'enabled' if ok else 'not available - using FFmpeg interpolation'}")
        save_state(rife_checked=True, rife_ok=ok)

    # PyTorch AI engine: best quality (face recovery + stronger upscalers), NVIDIA only.
    if first or not state.get("torch_checked"):
        gpus = nvidia_gpus()
        ok = False
        if gpus:
            try:
                ok = install_ai_runtime()
            except Exception as e:  # noqa: BLE001 - optional, the Vulkan engine still works
                print(f"    could not be installed: {e}")
        print(f"    PyTorch AI engine (faces + Pro models): "
              f"{'enabled' if ok else ('not available' if gpus else 'needs an NVIDIA GPU - skipped')}")
        save_state(torch_checked=True, torch_ok=ok)

    if not state.get("shortcut_done"):
        if create_desktop_shortcut() and not quiet:
            print("    Desktop shortcut created: 'AI Video Enhancer'")
        save_state(shortcut_done=True)

    save_state(setup_done=True)
    if pending and not quiet:
        print("\n  Setup complete.\n")
    return load_state()
