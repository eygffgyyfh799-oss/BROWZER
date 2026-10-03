"""Minimal local web UI (standard library only)."""

from __future__ import annotations

import json
import queue
import re
import shutil
import threading
import uuid
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlparse

from . import APP_NAME, __version__
from .pipeline import (SUPPORTED_EXTENSIONS, EnhanceError, EnhanceOptions, enhance,
                       probe, system_check, target_size)

STATIC = Path(__file__).resolve().parent / "static"
WORK_DIR = Path.home() / ".video-enhancer"
MAX_UPLOAD = 8 * 1024 ** 3  # 8 GB

jobs: dict[str, dict] = {}
job_queue: "queue.Queue[str]" = queue.Queue()
lock = threading.Lock()


def _update(job_id: str, **fields) -> None:
    with lock:
        jobs[job_id].update(fields)


def worker() -> None:
    while True:
        job_id = job_queue.get()
        job = jobs[job_id]
        _update(job_id, status="processing", stage="analyzing")
        try:
            enhance(job["input"], job["output"], job["options"],
                    lambda frac, label: _update(job_id, progress=round(frac * 100, 1), stage=label))
            _update(job_id, status="done", progress=100, stage="done")
        except Exception as e:  # noqa: BLE001 - surface any failure to the UI
            _update(job_id, status="error", error=str(e))
        finally:
            Path(job["input"]).unlink(missing_ok=True)
            job_queue.task_done()


class Handler(BaseHTTPRequestHandler):
    server_version = f"VideoEnhancer/{__version__}"

    def log_message(self, fmt, *args):  # quieter console
        pass

    def _json(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            body = (STATIC / "index.html").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/status":
            return self._json({"app": APP_NAME, "version": __version__, **system_check(),
                               "queue": job_queue.qsize()})
        m = re.fullmatch(r"/api/jobs/([0-9a-f]{32})(/download)?", path)
        if m and m.group(1) in jobs:
            job = jobs[m.group(1)]
            if not m.group(2):
                return self._json({k: job.get(k) for k in
                                   ("id", "status", "progress", "stage", "error", "name", "info")})
            out = Path(job["output"])
            if job["status"] != "done" or not out.exists():
                return self._json({"error": "not ready"}, 409)
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(out.stat().st_size))
            self.send_header("Content-Disposition", f"attachment; filename*=UTF-8''{quote(job['name'])}")
            self.end_headers()
            with out.open("rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/api/enhance":
            return self._json({"error": "not found"}, 404)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        filename = Path(q.get("filename", "video.mp4")).name
        ext = Path(filename).suffix.lower()
        if ext not in SUPPORTED_EXTENSIONS:
            return self._json({"error": "صيغة غير مدعومة. استخدم MP4 أو MOV أو WEBM"}, 400)
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_UPLOAD:
            return self._json({"error": "حجم الملف غير صالح"}, 400)

        opts = EnhanceOptions(engine=q.get("engine", "standard"), resolution=q.get("resolution", "1080p"),
                              fps=q.get("fps", "original"), preset=q.get("preset", "ugc"))
        try:
            opts.validate()
        except EnhanceError as e:
            return self._json({"error": str(e)}, 400)

        job_id = uuid.uuid4().hex
        WORK_DIR.mkdir(parents=True, exist_ok=True)
        src = WORK_DIR / f"{job_id}_in{ext}"
        dst = WORK_DIR / f"{job_id}_out.mp4"
        remaining = length
        with src.open("wb") as f:
            while remaining > 0:
                chunk = self.rfile.read(min(1 << 20, remaining))
                if not chunk:
                    break
                f.write(chunk)
                remaining -= len(chunk)
        if remaining:
            src.unlink(missing_ok=True)
            return self._json({"error": "انقطع الرفع"}, 400)

        try:
            info = probe(src)
        except EnhanceError as e:
            src.unlink(missing_ok=True)
            return self._json({"error": str(e)}, 400)
        w, h = target_size(info, opts.resolution)
        name = f"{Path(filename).stem}_enhanced_{opts.resolution}.mp4"
        jobs[job_id] = {"id": job_id, "status": "queued", "progress": 0, "stage": "queued",
                        "input": str(src), "output": str(dst), "options": opts, "name": name,
                        "info": {"src": f"{info.width}x{info.height}", "dst": f"{w}x{h}",
                                 "fps": round(info.fps, 2), "duration": round(info.duration, 1)}}
        job_queue.put(job_id)
        self._json({"id": job_id, "info": jobs[job_id]["info"]})


def serve(host: str = "127.0.0.1", port: int = 7860, open_browser: bool = True) -> None:
    threading.Thread(target=worker, daemon=True).start()
    httpd = ThreadingHTTPServer((host, port), Handler)
    url = f"http://{'localhost' if host in ('127.0.0.1', '0.0.0.0') else host}:{port}"
    status = system_check()
    print(f"\n  {APP_NAME} v{__version__}")
    print(f"  Web UI   : {url}")
    print(f"  FFmpeg   : {'OK' if status['ok'] else 'NOT FOUND - ' + status.get('error', '')}")
    print(f"  Upscaling: {'Real-ESRGAN (GPU)' if status['realesrgan'] else 'FFmpeg filters (CPU)'}")
    print(f"  FPS boost: {'RIFE (GPU)' if status['rife'] else 'FFmpeg minterpolate (CPU)'}")
    print(f"  Encoder  : {'NVENC (NVIDIA GPU)' if status['nvenc'] else 'x264 (CPU)'}")
    print("  Press Ctrl+C to stop.\n")
    if open_browser:
        threading.Timer(0.8, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")
    finally:
        httpd.server_close()
