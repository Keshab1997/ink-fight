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
# A detached blob at least this big and at least this light on average is
# generation haze (a grey ground smudge), not ink.
HAZE_MIN_PIXELS = 200
HAZE_MIN_LUMINANCE = 180

# In-betweens that bounding-box centring would misplace are registered on the
# planted foot instead. A scarf drawn longer than the neighbours', or a kick
# only half extended, moves the bounding box, and centring it then slides the
# whole body sideways. A listed frame is shifted sideways after alignment so
# that the centre of its lowest FOOT_BAND_ROWS rows lands halfway between its
# two neighbours' (docs/product/AI_CHARACTER_PROMPT_PACK.md §5b). The art is
# not touched; only its place on the canvas changes. Unlisted frames keep the
# plain bounding-box centring, byte for byte.
FOOT_BAND_ROWS = 40
FOOT_REGISTERED: dict[str, tuple[str, str]] = {
    # in-between: (frame before, frame after)
    "player_ink_fighter_heavy_kick_002.png": (
        "player_ink_fighter_heavy_kick_001.png",
        "player_ink_fighter_heavy_kick_003.png",
    ),
    "player_ink_fighter_idle_003.png": (
        "player_ink_fighter_idle_002.png",
        "player_ink_fighter_idle_004.png",
    ),
    "player_ink_fighter_block_004.png": (
        "player_ink_fighter_block_003.png",
        "player_ink_fighter_block_005.png",
    ),
    "bot_crimson_rival_block_004.png": (
        "bot_crimson_rival_block_003.png",
        "bot_crimson_rival_block_005.png",
    ),
}


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


def remove_detached_haze(image: Image.Image) -> Image.Image:
    """Drop faint grey blobs that float free of the drawing.

    A generation can leave a light-grey ground smudge under a lifted foot: too
    dark for the near-white border fill, and not ink either. Every opaque blob
    other than the largest one (the character) that is both big and light on
    average is cleared. Ink drops are dark, so the scarf's flicks survive, and
    none of the hand-cleaned frames has such a blob, so they come out unchanged.
    """
    width, height = image.size
    alpha = image.getchannel("A").tobytes()
    seen = bytearray(width * height)
    blobs: list[list[int]] = []
    for start in range(width * height):
        if seen[start] or not alpha[start]:
            continue
        seen[start] = 1
        blob = [start]
        queue = deque(blob)
        while queue:
            index = queue.popleft()
            x = index % width
            for neighbour, inside in (
                (index - 1, x > 0),
                (index + 1, x < width - 1),
                (index - width, index >= width),
                (index + width, index < width * (height - 1)),
            ):
                if inside and not seen[neighbour] and alpha[neighbour]:
                    seen[neighbour] = 1
                    blob.append(neighbour)
                    queue.append(neighbour)
        blobs.append(blob)
    if len(blobs) < 2:
        return image

    largest = max(blobs, key=len)
    rgb = image.convert("RGB").tobytes()
    pixels = image.load()
    for blob in blobs:
        if blob is largest or len(blob) < HAZE_MIN_PIXELS:
            continue
        total = sum(rgb[3 * i] + rgb[3 * i + 1] + rgb[3 * i + 2] for i in blob)
        if total / (3 * len(blob)) < HAZE_MIN_LUMINANCE:
            continue
        for index in blob:
            x, y = index % width, index // width
            red, green, blue, _ = pixels[x, y]
            pixels[x, y] = (red, green, blue, 0)
    return image


def align_to_runtime_canvas(image: Image.Image, shift_x: int = 0) -> Image.Image:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("the frame has no visible pixels after background removal")

    cropped = image.crop(bbox)
    # Normalise in both directions: a generation that came back with extra
    # white margin (or a non-square canvas) must land at the same on-screen
    # size as its neighbours, or the animation pops when it swaps in.
    scale = MAX_CHARACTER_SIZE / max(cropped.size)
    if scale != 1.0:
        cropped = cropped.resize(
            (round(cropped.width * scale), round(cropped.height * scale)),
            Image.Resampling.LANCZOS,
        )

    output = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    x = (CANVAS - cropped.width) // 2 + shift_x
    y = BASELINE_Y - cropped.height
    if x < 0 or x + cropped.width > CANVAS:
        raise ValueError("the registration shift pushes the frame off the canvas")
    output.alpha_composite(cropped, (x, y))
    return output


def planted_foot_x(image: Image.Image) -> float:
    """Mean x of the solid pixels in the lowest FOOT_BAND_ROWS rows of a frame."""
    alpha = image.getchannel("A")
    bottom = alpha.getbbox()[3] - 1
    top = max(bottom - FOOT_BAND_ROWS, 0)
    band = alpha.crop((0, top, image.width, bottom + 1)).tobytes()
    xs = [i % image.width for i, value in enumerate(band) if value > 128]
    return sum(xs) / len(xs)


def runtime_frame(source: Path, shift_x: int = 0) -> Image.Image:
    cleaned = remove_detached_haze(remove_border_background(Image.open(source)))
    return align_to_runtime_canvas(cleaned, shift_x)


def registration_shift(source: Path) -> int:
    """Sideways shift that lands a FOOT_REGISTERED frame between its neighbours."""
    neighbours = FOOT_REGISTERED.get(source.name)
    if neighbours is None:
        return 0
    if any(name in FOOT_REGISTERED for name in neighbours):
        raise ValueError(f"{source.name}: a neighbour is itself foot-registered")
    target = sum(
        planted_foot_x(runtime_frame(source.with_name(name))) for name in neighbours
    ) / len(neighbours)
    return round(target - planted_foot_x(runtime_frame(source)))


def process_frame(source: Path, destination: Path) -> None:
    runtime = runtime_frame(source, registration_shift(source))
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
