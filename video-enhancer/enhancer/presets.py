"""Engines, output options and content presets."""

ENGINES = {
    # Fast processing.
    "standard": {
        "label": "Standard",
        "nlmeans": False,
        "temporal_denoise": False,
        "mc_mode": "obmc",
        "me_mode": "bilat",
        "vsbmc": False,
        "sharpen_mul": 1.0,
        "edge_unsharp": False,
        "crf": 18,
        "x264_preset": "fast",
    },
    # Deep detail reconstruction (uses Real-ESRGAN when available).
    "pro": {
        "label": "Precise / Pro",
        "nlmeans": True,
        "temporal_denoise": True,
        "mc_mode": "aobmc",
        "me_mode": "bidir",
        "vsbmc": True,
        "sharpen_mul": 1.25,
        "edge_unsharp": True,
        "crf": 16,
        "x264_preset": "slow",
    },
}

RESOLUTIONS = {
    "1080p": {"label": "1080p (Full HD)", "short_side": 1080},
    "4k": {"label": "4K (UHD)", "short_side": 2160},
}

FPS_OPTIONS = {
    "original": None,
    "30": 30,
    "60": 60,
}

PRESETS = {
    "ai": {
        "label": "AI-generated clips",
        "deflicker": 5,            # AI clips often flicker between frames
        "deblock": 0,
        "denoise": (1.5, 1.5, 6, 6),  # luma_s, chroma_s, luma_t, chroma_t
        "nlmeans": 1.5,
        "sharpen": 0.55,
        "color": {"contrast": 1.03, "brightness": 0.0, "saturation": 1.05, "gamma": 1.0, "vibrance": 0.1},
        "ai_model": "realesr-animevideov3",
    },
    "old_film": {
        "label": "Old film",
        "deinterlace": True,
        "deflicker": 7,
        "deblock": 0.1,
        "denoise": (4, 3, 8, 6),   # heavy grain removal
        "nlmeans": 3.5,
        "sharpen": 0.5,
        "color": {"contrast": 1.08, "brightness": 0.01, "saturation": 1.15, "gamma": 1.02, "vibrance": 0.2},
        "ai_model": "realesrgan-x4plus",
    },
    "ugc": {
        "label": "Phone footage (UGC)",
        "deflicker": 0,
        "deblock": 0.15,           # heavy compression blocks from social apps
        "denoise": (2.5, 2, 5, 4),  # low-light grain
        "nlmeans": 2.5,
        "sharpen": 0.6,
        "color": {"contrast": 1.05, "brightness": 0.0, "saturation": 1.08, "gamma": 1.0, "vibrance": 0.15},
        "ai_model": "realesrgan-x4plus",
    },
    "none": {
        "label": "General",
        "deflicker": 0,
        "deblock": 0.08,
        "denoise": (1.5, 1.5, 4, 4),
        "nlmeans": 1.5,
        "sharpen": 0.45,
        "color": {"contrast": 1.0, "brightness": 0.0, "saturation": 1.0, "gamma": 1.0, "vibrance": 0},
        "ai_model": "realesrgan-x4plus",
    },
}
