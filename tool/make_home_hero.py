#!/usr/bin/env python3
"""Build the home screen's hero art from the delivered runtime poses.

The menu should show the same fighters the arena does, so instead of a
hand-drawn stand-in it crops two delivered poses to their alpha bounding box
(the 1024 px frames carry a lot of empty canvas) and resizes them to menu
scale. Run it after the character art changes:

    python3 tool/make_home_hero.py       # writes assets/ui/*.png

Everything it reads lives under `assets/characters/runtime/`, which is the
folder the asset pipeline marks as the one intended for the game.
"""
from __future__ import annotations

import os

from PIL import Image

OUT_DIR = os.path.join("assets", "ui")

# The two poses, chosen because they read as a fight rather than a pose sheet:
# the player's kick follows through with ink flying, the rival counters.
JOBS = [
    (
        "assets/characters/runtime/player_ink_fighter/heavy_kick/"
        "player_ink_fighter_heavy_kick_003.png",
        "home_player_kick.png",
    ),
    (
        "assets/characters/runtime/bot_crimson_rival/light_punch/"
        "bot_crimson_rival_light_punch_002.png",
        "home_rival_punch.png",
    ),
]

TARGET_HEIGHT = 520
PADDING = 12


def crop_to_content(path: str) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    box = image.getchannel("A").getbbox()
    if box is None:
        raise SystemExit(f"{path} is fully transparent")
    left, top, right, bottom = box
    return image.crop(
        (
            max(0, left - PADDING),
            max(0, top - PADDING),
            min(image.width, right + PADDING),
            min(image.height, bottom + PADDING),
        )
    )


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    for source, name in JOBS:
        cropped = crop_to_content(source)
        scale = TARGET_HEIGHT / cropped.height
        size = (round(cropped.width * scale), TARGET_HEIGHT)
        target = os.path.join(OUT_DIR, name)
        cropped.resize(size, Image.LANCZOS).save(target, optimize=True)
        print(
            f"{name:24} {cropped.size} -> {size}  "
            f"{os.path.getsize(target) // 1024} KB"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
