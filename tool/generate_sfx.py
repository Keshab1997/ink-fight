#!/usr/bin/env python3
"""Generate INK FIGHT's placeholder sound effects.

The cue list is exactly the one docs/technical/GAME_FEEL.md §4 specifies, so
each file here has a line in the design document behind it:

    light hit       ~80 ms  tick
    heavy hit      ~200 ms  thud + ink splat tail
    blocked                 wooden clack
    attack start            whoosh (thin for the jab, longer for the kick)
    jump / land             soft tap
    KO                      gong, then silence
    countdown / result      blip x3, then a short sting

Everything is synthesised from scratch here (noise, sine partials, envelopes)
so the repository carries no third-party audio and needs no licence review.
They are deliberately plain: placeholders that make the fight audible and
playable, meant to be replaced by recorded or designed audio later. Regenerate
with:

    python3 tool/generate_sfx.py            # writes assets/audio/*.wav

Format: mono, 22050 Hz, 16-bit PCM — under 60 KB each, the budget §4 sets.
"""
from __future__ import annotations

import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join("assets", "audio")
PEAK = 0.85


# --------------------------------------------------------------------------
# tiny synthesis kit
# --------------------------------------------------------------------------
def _frames(ms: int) -> int:
    return int(RATE * ms / 1000)


def noise_frames_count(ms: int, seed: int) -> list[float]:
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(_frames(ms))]


def lowpass(signal: list[float], cutoff_hz: float) -> list[float]:
    """One-pole low pass: the workhorse for every soft/thuddy body."""
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    out = []
    last = 0.0
    for sample in signal:
        last += alpha * (sample - last)
        out.append(last)
    return out


def highpass(signal: list[float], cutoff_hz: float) -> list[float]:
    low = lowpass(signal, cutoff_hz)
    return [s - l for s, l in zip(signal, low)]


def bandpass(signal: list[float], low_hz: float, high_hz: float) -> list[float]:
    """The band a phone speaker can actually reproduce: low-mid body."""
    return highpass(lowpass(signal, high_hz), low_hz)


def decay(length: int, tau_ms: float, attack_ms: float = 2.0) -> list[float]:
    """Exponential decay with a short linear attack, so nothing clicks."""
    tau = max(tau_ms, 1.0) / 1000.0 * RATE
    attack = max(1, _frames(int(attack_ms)))
    out = []
    for i in range(length):
        env = math.exp(-i / tau)
        if i < attack:
            env *= i / attack
        out.append(env)
    return out


def tone(ms: int, hz: float, sweep_to: float | None = None) -> list[float]:
    """A sine, optionally gliding from hz to sweep_to across the duration."""
    n = _frames(ms)
    end = hz if sweep_to is None else sweep_to
    out = []
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        freq = hz + (end - hz) * t
        phase += 2.0 * math.pi * freq / RATE
        out.append(math.sin(phase))
    return out


def mix(*layers: list[float]) -> list[float]:
    """Sum layers of different lengths into one track."""
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, sample in enumerate(layer):
            out[i] += sample
    return out


def mul(signal: list[float], envelope: list[float]) -> list[float]:
    return [s * envelope[i] for i, s in enumerate(signal)]


def gain(signal: list[float], factor: float) -> list[float]:
    return [s * factor for s in signal]


def normalize(signal: list[float], peak: float = PEAK) -> list[float]:
    top = max((abs(s) for s in signal), default=0.0)
    if top == 0.0:
        return signal
    scale = peak / top
    return [s * scale for s in signal]


def smooth_edges(signal: list[float], fade_ms: float = 3.0) -> list[float]:
    fade = max(1, _frames(int(fade_ms)))
    out = list(signal)
    for i in range(min(fade, len(out))):
        k = i / fade
        out[i] *= k
        out[-1 - i] *= k
    return out


def write(name: str, signal: list[float], peak: float = PEAK) -> None:
    path = os.path.join(OUT_DIR, name)
    os.makedirs(OUT_DIR, exist_ok=True)
    samples = smooth_edges(normalize(signal, peak))
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(RATE)
        fh.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
                for s in samples
            )
        )
    print(f"{name:22} {os.path.getsize(path):>6} bytes  {len(samples) / RATE * 1000:>5.0f} ms")


# --------------------------------------------------------------------------
# the cues (GAME_FEEL §4, in the table's order)
# --------------------------------------------------------------------------
def light_hit() -> list[float]:
    body = mul(lowpass(noise_frames_count(80, 11), 3200), decay(_frames(80), 14))
    click = mul(tone(50, 1150), decay(_frames(50), 12))
    return mix(gain(body, 1.0), gain(click, 0.5))


def heavy_hit() -> list[float]:
    thud = mul(tone(220, 76), decay(_frames(220), 70))
    chest = mul(tone(220, 150), decay(_frames(220), 45))
    body = mul(lowpass(noise_frames_count(220, 23), 900), decay(_frames(220), 55))
    splat = mul(
        lowpass(noise_frames_count(420, 29), 1400),
        decay(_frames(420), 150, attack_ms=18.0),
    )
    return mix(gain(thud, 3.0), gain(chest, 0.8), gain(body, 1.1), gain(splat, 0.45))


def blocked() -> list[float]:
    first = mul(lowpass(noise_frames_count(70, 31), 2600), decay(_frames(70), 16))
    second = mul(lowpass(noise_frames_count(60, 37), 2000), decay(_frames(60), 20))
    wood = mul(tone(60, 430), decay(_frames(60), 18))
    rest = [0.0] * _frames(45)
    return mix(
        gain(first, 1.2),
        gain(mul(wood, [1.0] * _frames(60)), 0.7),
        rest + gain(second, 0.9),
    )


def whoosh_light() -> list[float]:
    # Body first, air second. The first version was noise above 500 Hz only —
    # a phone speaker barely moves there, so a whiff (the swing that lands on
    # nothing) came across as silence, and silence is the one thing a whiff
    # must never sound like. The 180–1100 Hz band carries it on a phone, the
    # top band keeps the cut on headphones, and the falling gust ties the two
    # together into one gesture.
    n = 240
    body = mul(bandpass(noise_frames_count(n, 42), 180, 1100),
               decay(_frames(n), 170, attack_ms=22.0))
    air = mul(highpass(noise_frames_count(n, 41), 1200),
              decay(_frames(n), 90, attack_ms=18.0))
    gust = mul(tone(n, 560, 190), decay(_frames(n), 150, attack_ms=30.0))
    return mix(body, gain(air, 0.5), gain(gust, 0.5))


def whoosh_heavy() -> list[float]:
    # The kick's sweep, same two bands an octave down and half a second of
    # tail — unmistakably bigger than the jab's, still only air.
    n = 380
    body = mul(bandpass(noise_frames_count(n, 44), 130, 780),
               decay(_frames(n), 200, attack_ms=28.0))
    air = mul(highpass(noise_frames_count(n, 43), 900),
              decay(_frames(n), 130, attack_ms=30.0))
    gust = mul(tone(n, 380, 110), decay(_frames(n), 190, attack_ms=40.0))
    low = mul(lowpass(noise_frames_count(n, 47), 400),
              decay(_frames(n), 210, attack_ms=35.0))
    return mix(body, gain(air, 0.45), gain(gust, 0.6), gain(low, 0.45))


def step_tap() -> list[float]:
    thump = mul(tone(70, 165), decay(_frames(70), 26))
    tick = mul(lowpass(noise_frames_count(40, 53), 1800), decay(_frames(40), 9))
    return mix(gain(thump, 1.0), gain(tick, 0.35))


def ko_gong() -> list[float]:
    # A gong is a low fundamental plus inharmonic partials that ring out at
    # different rates; the slow beating between them is the metal.
    partials = [(180.0, 1.00, 620.0), (271.0, 0.62, 470.0), (383.0, 0.44, 380.0),
                (545.0, 0.26, 260.0), (726.0, 0.14, 180.0)]
    layers = []
    for hz, amp, tau in partials:
        layers.append(mul(tone(1000, hz), decay(_frames(1000), tau, attack_ms=5.0)))
        layers.append(gain(layers[-1], 0.0))  # placeholder, keeps lengths obvious
    struck = mul(lowpass(noise_frames_count(1000, 59), 300), decay(_frames(1000), 60, attack_ms=4.0))
    return mix(gain(mix(*layers), 1.0), gain(struck, 0.8))


def countdown_blip() -> list[float]:
    body = tone(110, 880, 830)
    body = mul(body, decay(_frames(110), 65))
    sparkle = mul(tone(110, 1320), decay(_frames(110), 40))
    return mix(gain(body, 1.0), gain(sparkle, 0.25))


def round_sting() -> list[float]:
    first = mul(tone(200, 660), decay(_frames(200), 90))
    second = [0.0] * _frames(120) + mul(tone(330, 990), decay(_frames(330), 150))
    fifth = [0.0] * _frames(120) + mul(tone(330, 1485), decay(_frames(330), 120))
    return mix(gain(first, 1.0), gain(second, 0.9), gain(fifth, 0.3))


CUES = {
    "hit_light.wav": light_hit,
    "hit_heavy.wav": heavy_hit,
    "blocked.wav": blocked,
    "whoosh_light.wav": whoosh_light,
    "whoosh_heavy.wav": whoosh_heavy,
    "step_tap.wav": step_tap,
    "ko_gong.wav": ko_gong,
    "countdown_blip.wav": countdown_blip,
    "round_sting.wav": round_sting,
}


def main() -> int:
    for name, build in CUES.items():
        write(name, build())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
