"""GPU post-processing: everything after the AI model runs on the graphics card.

On the CPU these steps (4K resize, sharpening, color, temporal denoise, debanding,
RGB->YUV) ran at ~4 fps and were the real bottleneck; on the GPU they take a few ms.
All functions take / return float tensors shaped (1, 3, H, W) in [0, 1].
"""

from __future__ import annotations

import math

import torch
import torch.nn.functional as F

# BT.709 luma weights.
KR, KG, KB = 0.2126, 0.7152, 0.0722


def resize(x: torch.Tensor, width: int, height: int) -> torch.Tensor:
    if x.shape[-1] == width and x.shape[-2] == height:
        return x
    down = width < x.shape[-1]
    # Antialiased bicubic for downscaling (no aliasing / moire), plain bicubic for upscaling.
    y = F.interpolate(x.float(), size=(height, width), mode="bicubic", align_corners=False, antialias=down)
    return y.clamp_(0, 1).to(x.dtype)


def cas(x: torch.Tensor, strength: float) -> torch.Tensor:
    """Contrast Adaptive Sharpening (AMD FidelityFX CAS): sharpens detail without halos."""
    if strength <= 0:
        return x
    p = F.pad(x, (1, 1, 1, 1), mode="replicate")
    b, d, e = p[..., :-2, 1:-1], p[..., 1:-1, :-2], p[..., 1:-1, 1:-1]
    f, h = p[..., 1:-1, 2:], p[..., 2:, 1:-1]
    mn = torch.minimum(torch.minimum(torch.minimum(b, d), torch.minimum(f, h)), e)
    mx = torch.maximum(torch.maximum(torch.maximum(b, d), torch.maximum(f, h)), e)
    amp = (torch.minimum(mn, 1.0 - mx) / mx.clamp_min(1e-4)).clamp_(0, 1).sqrt_()
    peak = -1.0 / (8.0 - 3.0 * min(1.0, strength))
    w = amp * peak
    return ((w * (b + d + f + h) + e) / (1.0 + 4.0 * w)).clamp_(0, 1)


def _to_ycbcr(x: torch.Tensor):
    r, g, b = x[:, 0:1], x[:, 1:2], x[:, 2:3]
    y = KR * r + KG * g + KB * b
    return y, (b - y) / (2 * (1 - KB)), (r - y) / (2 * (1 - KR))


def _to_rgb(y, cb, cr) -> torch.Tensor:
    r = y + 2 * (1 - KR) * cr
    b = y + 2 * (1 - KB) * cb
    g = (y - KR * r - KB * b) / KG
    return torch.cat([r, g, b], dim=1).clamp_(0, 1)


def color(x: torch.Tensor, c: dict) -> torch.Tensor:
    """Same controls as FFmpeg eq + vibrance: contrast, brightness, saturation, gamma, vibrance."""
    if (c.get("contrast", 1) == 1 and c.get("brightness", 0) == 0 and c.get("saturation", 1) == 1
            and c.get("gamma", 1) == 1 and not c.get("vibrance")):
        return x
    y, cb, cr = _to_ycbcr(x)
    y = ((y - 0.5) * c.get("contrast", 1.0) + 0.5 + c.get("brightness", 0.0)).clamp_(0, 1)
    if c.get("gamma", 1.0) != 1.0:
        y = y.pow(1.0 / c["gamma"])
    sat = c.get("saturation", 1.0)
    if c.get("vibrance"):
        # Boost dull colors more than already saturated ones (protects skin tones).
        chroma = torch.sqrt(cb * cb + cr * cr) * 2.0
        sat = sat * (1.0 + c["vibrance"] * (1.0 - chroma.clamp(0, 1)))
    return _to_rgb(y, cb * sat, cr * sat)


class TemporalSmoother:
    """Motion-adaptive temporal filter (like hqdn3d's temporal part + deflicker):
    tiny frame-to-frame differences (flicker, AI shimmer) are averaged,
    real motion is left untouched. Resets on scene cuts."""

    def __init__(self, strength: float = 0.45, threshold: float = 4.0 / 255.0):
        self.strength, self.threshold = strength, threshold
        self.prev: torch.Tensor | None = None

    def __call__(self, x: torch.Tensor) -> torch.Tensor:
        prev = self.prev
        if prev is None or prev.shape != x.shape or float((x - prev).abs().mean()) > 0.08:
            self.prev = x
            return x
        d = prev - x
        w = self.strength * torch.exp(-(d / self.threshold).square_())
        out = x + w * d
        self.prev = out
        return out


def to_yuv420(x: torch.Tensor) -> torch.Tensor:
    """RGB [0,1] -> planar YUV 4:2:0, BT.709 limited range, 8-bit with dithering (prevents banding).
    Returns one flat uint8 tensor: Y plane, then U, then V (what FFmpeg's yuv420p expects)."""
    y, cb, cr = _to_ycbcr(x.float())
    cb = F.avg_pool2d(cb, 2)
    cr = F.avg_pool2d(cr, 2)
    planes = (16.0 + 219.0 * y, 128.0 + 224.0 * cb, 128.0 + 224.0 * cr)
    out = []
    for p in planes:
        noise = torch.rand_like(p) - torch.rand_like(p)  # triangular dither, +-1 LSB
        out.append((p + 0.5 * noise).round_().clamp_(0, 255).to(torch.uint8).flatten())
    return torch.cat(out)


# --------------------------------------------------------------------------- faces

_MASK_CLASSES = [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0]  # facexlib ParseNet face classes


def _gaussian_kernel(size: int, sigma: float, device, dtype) -> torch.Tensor:
    ax = torch.arange(size, device=device, dtype=torch.float32) - (size - 1) / 2
    k = torch.exp(-(ax ** 2) / (2 * sigma ** 2))
    return (k / k.sum()).to(dtype)


def face_masks(parse_net, faces: torch.Tensor) -> torch.Tensor:
    """Soft face masks (N, 1, 512, 512) from the ParseNet segmentation, blurred like facexlib."""
    logits = parse_net((faces.float() - 0.5) / 0.5)[0]
    classes = torch.tensor(_MASK_CLASSES, device=faces.device, dtype=torch.float32)
    mask = classes[logits.argmax(dim=1)].unsqueeze(1)
    k = _gaussian_kernel(101, 11.0, faces.device, torch.float32)
    for _ in range(2):
        mask = F.conv2d(F.pad(mask, (50, 50, 0, 0), mode="reflect"), k.view(1, 1, 1, -1))
        mask = F.conv2d(F.pad(mask, (0, 0, 50, 50), mode="reflect"), k.view(1, 1, -1, 1))
    t = 10
    mask[..., :t, :] = 0
    mask[..., -t:, :] = 0
    mask[..., :, :t] = 0
    mask[..., :, -t:] = 0
    return mask


def paste_faces(frame: torch.Tensor, faces: torch.Tensor, masks: torch.Tensor, affines: list,
                fx: float, fy: float) -> torch.Tensor:
    """Warp restored 512x512 faces back onto the output frame (on the GPU) and blend them.

    affines: 2x3 matrices mapping input-frame pixels -> face-crop pixels (from facexlib).
    fx, fy:  output size / input size.
    """
    _, _, H, W = frame.shape
    size = faces.shape[-1]
    out = frame
    for i, a in enumerate(affines):
        a = torch.as_tensor(a, dtype=torch.float32)
        # Bounding box of the face crop in output coordinates.
        full = torch.cat([a, torch.tensor([[0.0, 0.0, 1.0]])])
        inv = torch.linalg.inv(full)
        corners = torch.tensor([[0, 0, 1], [size, 0, 1], [0, size, 1], [size, size, 1]], dtype=torch.float32)
        src = (inv @ corners.T)[:2]
        x0 = max(0, int(math.floor(float(src[0].min()) * fx)) - 2)
        x1 = min(W, int(math.ceil(float(src[0].max()) * fx)) + 2)
        y0 = max(0, int(math.floor(float(src[1].min()) * fy)) - 2)
        y1 = min(H, int(math.ceil(float(src[1].max()) * fy)) + 2)
        if x1 <= x0 or y1 <= y0:
            continue
        dev = frame.device
        us = (torch.arange(x0, x1, device=dev, dtype=torch.float32) + 0.5) / fx - 0.5
        vs = (torch.arange(y0, y1, device=dev, dtype=torch.float32) + 0.5) / fy - 0.5
        vv, uu = torch.meshgrid(vs, us, indexing="ij")
        ad = a.to(dev)
        face_x = ad[0, 0] * uu + ad[0, 1] * vv + ad[0, 2]
        face_y = ad[1, 0] * uu + ad[1, 1] * vv + ad[1, 2]
        grid = torch.stack([(2 * face_x + 1) / size - 1, (2 * face_y + 1) / size - 1], dim=-1).unsqueeze(0)
        face = F.grid_sample(faces[i:i + 1].float(), grid, mode="bicubic", padding_mode="zeros", align_corners=False)
        m = F.grid_sample(masks[i:i + 1].float(), grid, mode="bilinear", padding_mode="zeros", align_corners=False)
        region = out[..., y0:y1, x0:x1].float()
        blended = (m * face.clamp(0, 1) + (1 - m) * region).to(out.dtype)
        if out is frame:
            out = frame.clone()
        out[..., y0:y1, x0:x1] = blended
    return out
