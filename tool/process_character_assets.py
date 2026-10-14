#!/usr/bin/env python3
"""Clean approved AI character frames into baseline-aligned runtime PNGs.

This deliberately removes only near-white pixels connected to the image border.
White parts enclosed by the character's ink outline remain intact. The original
AI outputs are never modified; runtime files are written under
assets/characters/runtime/.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


CANVAS = 1024
BASELINE_Y = 900
MAX_CHARACTER_SIZE = 860


def is_background(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    return alpha > 0 and red >= 245 and green >= 245 and blue >= 245


def remove_border_background(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def add_if_background(x: int, y: int) -> None:
        index = y * width + x
        if not visited[index] and is_background(pixels[x, y]):
            visited[index] = 1
            queue.append((x, y))

    for x in range(width):
        add_if_background(x, 0)
        add_if_background(x, height - 1)
    for y in range(height):
        add_if_background(0, y)
        add_if_background(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                add_if_background(nx, ny)

    for y in range(height):
        for x in range(width):
            if visited[y * width + x]:
                red, green, blue, _ = pixels[x, y]
                pixels[x, y] = (red, green, blue, 0)

    return image


def align_to_runtime_canvas(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("the frame has no visible pixels after background removal")

    cropped = image.crop(bbox)
    scale = min(1.0, MAX_CHARACTER_SIZE / max(cropped.size))
    if scale != 1.0:
        cropped = cropped.resize(
            (round(cropped.width * scale), round(cropped.height * scale)),
            Image.Resampling.LANCZOS,
        )

    output = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    x = (CANVAS - cropped.width) // 2
    y = BASELINE_Y - cropped.height
    output.alpha_composite(cropped, (x, y))
    return output


def process_frame(source: Path, destination: Path) -> None:
    cleaned = remove_border_background(Image.open(source))
    runtime = align_to_runtime_canvas(cleaned)
    destination.parent.mkdir(parents=True, exist_ok=True)
    runtime.save(destination, format="PNG", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=Path("assets/characters/originals"),
        help="folder containing untouched AI frame outputs",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/characters/runtime"),
        help="folder for cleaned runtime frames",
    )
    args = parser.parse_args()

    frame_count = 0
    for character_dir in sorted(args.source.iterdir()):
        if not character_dir.is_dir():
            continue
        character = character_dir.name
        prefix = f"{character}_"
        for source in sorted(character_dir.glob(f"{character}_*.png")):
            relative_name = source.stem.removeprefix(prefix)
            animation, frame = relative_name.rsplit("_", 1)
            if not frame.isdigit():
                continue
            destination = args.output / character / animation / source.name
            process_frame(source, destination)
            frame_count += 1
            print(f"processed {source} -> {destination}")

    print(f"processed {frame_count} frame(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
