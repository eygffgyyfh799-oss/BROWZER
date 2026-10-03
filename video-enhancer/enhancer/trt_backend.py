"""TensorRT acceleration for the upscaling models.

The PyTorch model is exported to ONNX once, then compiled by TensorRT (FP16) into an
engine tuned for this exact GPU and input resolution. Engines are cached on disk, so
only the first video at a new resolution pays the build time (about 1-5 minutes).
Inputs / outputs stay on the GPU (no copies through system memory).
"""

from __future__ import annotations

import copy
import re
from pathlib import Path

import torch


def available() -> bool:
    try:
        import tensorrt  # noqa: F401

        return torch.cuda.is_available()
    except Exception:  # noqa: BLE001
        return False


def _safe(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", text)


def export_onnx(model: torch.nn.Module, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    model = copy.deepcopy(model).float().eval().cpu()  # never touch the live GPU model
    dummy = torch.rand(1, 3, 64, 64)
    torch.onnx.export(model, dummy, str(tmp), input_names=["input"], output_names=["output"],
                      dynamic_axes={"input": {2: "h", 3: "w"}, "output": {2: "H", 3: "W"}},
                      opset_version=17, dynamo=False)
    tmp.replace(path)


def build_engine(onnx_path: Path, engine_path: Path, width: int, height: int) -> None:
    import tensorrt as trt

    logger = trt.Logger(trt.Logger.ERROR)
    builder = trt.Builder(logger)
    network = builder.create_network(0)
    parser = trt.OnnxParser(network, logger)
    if not parser.parse(onnx_path.read_bytes()):
        errors = "; ".join(str(parser.get_error(i)) for i in range(parser.num_errors))
        raise RuntimeError(f"ONNX parse failed: {errors}")
    config = builder.create_builder_config()
    config.set_flag(trt.BuilderFlag.FP16)
    free, _ = torch.cuda.mem_get_info()
    config.set_memory_pool_limit(trt.MemoryPoolType.WORKSPACE, int(min(4 << 30, free * 0.6)))
    profile = builder.create_optimization_profile()
    shape = (1, 3, height, width)
    profile.set_shape("input", shape, shape, shape)  # static shape = fastest kernels
    config.add_optimization_profile(profile)
    data = builder.build_serialized_network(network, config)
    if data is None:
        raise RuntimeError("TensorRT could not build the engine (not enough VRAM for this resolution?)")
    engine_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = engine_path.with_suffix(".tmp")
    tmp.write_bytes(bytes(data))
    tmp.replace(engine_path)


class TRTUpscaler:
    def __init__(self, model: torch.nn.Module, model_name: str, scale: int, width: int, height: int,
                 cache_dir: Path, on_build=None):
        import tensorrt as trt

        self.scale, self.width, self.height = scale, width, height
        gpu = _safe(torch.cuda.get_device_name(0))
        onnx_path = cache_dir / f"{model_name}.onnx"
        self.engine_path = cache_dir / f"{model_name}_{width}x{height}_trt{_safe(trt.__version__)}_{gpu}.engine"
        if self.engine_path.with_suffix(".bad").exists():
            raise RuntimeError("TensorRT engine failed the quality check before; using PyTorch")
        if not self.engine_path.exists():
            if on_build:
                on_build()
            if not onnx_path.exists():
                export_onnx(model, onnx_path)
            build_engine(onnx_path, self.engine_path, width, height)

        self._runtime = trt.Runtime(trt.Logger(trt.Logger.ERROR))
        self._engine = self._runtime.deserialize_cuda_engine(self.engine_path.read_bytes())
        if self._engine is None:
            raise RuntimeError("Cached TensorRT engine could not be loaded")
        self._ctx = self._engine.create_execution_context()
        self._ctx.set_input_shape("input", (1, 3, height, width))
        self._in = torch.empty((1, 3, height, width), dtype=torch.float32, device="cuda")
        self._out = torch.empty((1, 3, height * scale, width * scale), dtype=torch.float32, device="cuda")
        self._ctx.set_tensor_address("input", self._in.data_ptr())
        self._ctx.set_tensor_address("output", self._out.data_ptr())

    def mark(self, ok: bool) -> None:
        """Remember the quality check result next to the engine."""
        self.engine_path.with_suffix(".ok" if ok else ".bad").write_text("1")

    @property
    def verified(self) -> bool | None:
        if self.engine_path.with_suffix(".ok").exists():
            return True
        if self.engine_path.with_suffix(".bad").exists():
            return False
        return None

    def __call__(self, x: torch.Tensor) -> torch.Tensor:
        self._in.copy_(x)
        stream = torch.cuda.current_stream()
        if not self._ctx.execute_async_v3(stream.cuda_stream):
            raise RuntimeError("TensorRT execution failed")
        return self._out.to(x.dtype)
