# Game Feel — the "think like a video game" pass

Source of truth: `docs/product/GAME_DESIGN_DOCUMENT.md` §7 *Feel targets* (small
hit-stop, distinct light/heavy impact sounds, ink burst + line shake + a brief
camera response on strong attacks, disableable haptics, and nothing that hides
the fighters or the health state). This document turns those targets into
numbers, so the work is implemented once instead of guessed at.

Status: **specification**. Nothing here is implemented yet except where marked
"exists".

## 0. The bug that matters most — animation is not the fight

The arena plays each attack as a uniform sprite cycle, but `MatchRules` gives
each attack a startup / active / recovery window. They do not line up:

| Move | Frame data (the hitbox) | What the sprite does today | Result |
|---|---|---|---|
| light punch | opens 90 ms, closes 160 ms, ends 350 ms | 5 frames + 2 idle bookends × 90 ms = **630 ms** | hitbox opens while the sprite is still winding up; the sprite keeps swinging 280 ms after the player can already walk |
| heavy kick | opens 240 ms, closes 330 ms, ends 670 ms | 6 frames + 2 idle bookends × 120 ms = **960 ms** | contact frame lands at ~480 ms, nearly twice the time the rules took |

This is what "the fighting feels rough" is made of. Everything below is
polish; **this one is the fix.** The contact frame must be on screen at the
exact instant the hitbox opens, and the animation must end when the move ends.

## 1. Frame-data-driven animation

Flame can hold a frame for a chosen time, per frame
(`SpriteAnimationFrame(sprite, stepTime: …)`), so the cycles below are exact
recipes derived from `MatchRules.standard` — no uniform `stepTime`.

**light_punch — 7 frames, 350 ms total** (startup 90 / active 70 / recovery 190):

| Frame | Pose (art bible) | Holds for | Window |
|---|---|---|---|
| 000 | wind-up | 30 ms | startup |
| 001 | launch (in-between) | 30 ms | startup |
| 002 | extension | 30 ms | startup (hitbox opens at 90 ms) |
| 003 | **contact** | **70 ms** | active — the hitbox is open exactly here |
| 004 | recoil | 65 ms | recovery |
| 005 | back toward guard (in-between) | 60 ms | recovery |
| 006 | recovery | 65 ms | recovery → back to idle |

**heavy_kick — 6 frames, 670 ms total** (startup 240 / active 90 / recovery 340):

| Frame | Pose | Holds for | Window |
|---|---|---|---|
| 000 | wind-up | 80 ms | startup |
| 001 | lift | 80 ms | startup |
| 002 | extension | 80 ms | startup (hitbox opens at 240 ms) |
| 003 | **contact** | **90 ms** | active |
| 004 | recoil | 170 ms | recovery |
| 005 | recovery | 170 ms | recovery → idle |

Other cycles: **block** (raise 90 ms → loop frames 1–2 at 140 ms while the
guard is held → release 120 ms) · **hurt** (000 at 0, 001 at 70, 002 at 150,
then hold the last frame until hitstun ends — 220 ms light, 420 ms heavy) ·
**jump** (takeoff 100, rise 150, apex 150, fall 160, landing 140 = 700 ms =
`jumpMs`) · **walk** (see §6; 8 frames since the in-betweens) · **idle** (one
560 ms breath — the old 4 × 140 ms — spread evenly over however many frames are
delivered: the rival's 6 hold ≈93 ms each, the player's 5 hold 112 ms until his
last in-between lands).

Rule of thumb for any future move: the contact frame sits inside the active
window, and `sum(frame holds) == totalMs` from the rules table.

## 2. Hit-stop (impact freeze)

On a **confirmed** hit (not a whiff, not a block), hold the whole simulation
still for a few frames. This is the single cheapest thing that makes a hit feel
like it has weight.

| Event | Freeze |
|---|---|
| light punch lands | 70 ms |
| heavy kick lands | 110 ms |
| attack blocked | 50 ms |
| KO blow | 250 ms then the slow-mo in §5 |

Implementation shape: the arena keeps `_hitStopRemainingMs`; while it is
positive it consumes real time and calls the children/`_match.tick` with a
scaled dt of 0, so fighters and the match clock stand still. The **effects of
§3 keep running** — freeze the fighters, never the impact.

Needs a hit event out of `MatchController` (hit / blocked / whiff, which
fighter, and where along x). It is the only rule-layer change this spec asks
for; the controller already knows all of it at the moment it resolves a hit.

## 3. Ink burst, impact mark, line shake, camera response

Drawn in the arena's own `render()` (not as Flame children), so hit-stop can
freeze the fighters without freezing the effect.

| Effect | Light | Heavy |
|---|---|---|
| ink burst | 7 blobs, r 6–18 px, 120 px/s, life 180 ms | 12 blobs, r 10–30 px, 200 px/s, life 260 ms |
| colour | black `#101010` | black + 2 crimson `#C51F3A` flecks |
| line shake | 3 px amplitude, 140 ms | 7 px amplitude, 240 ms |
| camera response | 1 px nudge | 4 px pull, 180 ms |

- Blob shapes reuse the ink language already in
  `lib/widgets/doodle_fighter_painter.dart` (`_drawInkBurst`).
- A **blocked** hit gets the restrained black-and-white impact mark from the
  block frames (art bible §4) for 90 ms, and no burst.
- Shake: decaying sine along the hit vector (x only), applied as a
  `canvas.save()/translate()` around the world, released before the HUD draws.
  The HUD is a Flutter widget above the game, so it stays still for free.
- Budget: every effect stays within ±15 % of the fighters' height and never
  overlaps the health bars (GDD §7 "no visual effect should hide the fighters
  or health state").

## 4. Haptics and sound

Both are GDD requirements, both must be **independently disableable**
(GDD §129). Both now exist and are wired: haptics fire from the hit events,
and the nine cues below play through `FightSounds` — the arena speaks cues and
never file names, so the assets can be replaced without touching a call site.

| Event | Haptic | Sound |
|---|---|---|
| light hit | `lightImpact` | short tick, ~80 ms |
| heavy hit | `heavyImpact` | low thud, ~200 ms + ink splat tail |
| blocked | `selectionClick` | wooden clack |
| attack start | — | whoosh (light 240 ms, heavy 380 ms) |
| footfall (walking) | — | soft tap, one per stride |
| jump / land | `selectionClick` | soft tap |
| KO | `heavyImpact` twice, 90 ms apart | gong, then silence |
| countdown / result | — | blip ×3, then a short sting |

The cues are synthesised by `tool/generate_sfx.py` (mono 22050 Hz 16-bit,
under 60 KB each, no third-party audio): deliberately plain placeholders that
make the fight audible, written to be replaced by recorded or designed audio
later. Two rules that came out of playing the fight and are easy to get wrong:

- **A whiff must be heard.** `whoosh_light` was noise above 500 Hz — a band a
  phone speaker barely moves — so an empty swing read as silence. Both whooshes
  are body-first now (the light one keeps ~60% of its energy under 900 Hz).
- **Cues must land on their frame.** Playback goes through one pre-warmed
  `AudioPool` per cue: setting each player's source once, in `warmUp`, is the
  difference between a tap arriving with the foot and arriving after it.

Both are gated by real settings: `InkSettings.soundOn` and `hapticsOn` are the
switches, mirrored into the arena per frame, and a test asserts that turning
sound off changes nothing about the simulation. The switches are still
session-only (see the README's known gaps) — persisting them needs a storage
dependency, so it waits on Keshab.

## 5. Round flow — the part that already half-exists

| Moment | Today | Target |
|---|---|---|
| countdown (2000 ms) | number | 4 beats of 500 ms: 3 · 2 · 1 · FIGHT!, brush-stroke style |
| KO blow | round-end card appears | slow-mo 0.25× for 350 ms → hit-stop 250 ms → card stamps in |
| loser / winner | end pose (`_endPose`, exists) | loser plays knockdown→defeat, winner plays victory; the rival's defeat cycle now exists (96/96 frames landed) |
| rematch | exists | keep as is |

## 6. Movement detail

- **Walk**: the cycle must not skate. Measure the stride actually drawn in the
  frames (front foot spread) and set the per-frame step so the feet move the
  ground the controller does: `cycleMs = (unitsPerCycle / walkSpeed) * 1000`,
  `stepTime = cycleMs / frames` (8 walk frames since the in-betweens). Current `0.09 s` × 6 = 540 ms → 42 arena units at
  `walkSpeed = 78`; the cycle reads right only if the art covers that.
- **Landing**: a 90 ms squash (scale.y 0.94) on the landing frame, plus a small
  ink puff at the feet. No control change.
- Acceleration stays out of scope: the rules are instant-speed by design and
  the tests pin it.

## 7. Difficulty — a fun bug, not a feel bug

`InkFightBattleGame` defaults to **`BotProfile.easy`**, and GDD §8 says
**Normal is the default**. Easy is deliberately passive (35 % hesitation,
1300 ms attack cooldown), which is a large part of why a fight currently feels
flat. Default to Normal, and let the player pick Easy/Normal/Hard — the
profiles and the tests for all three already exist.

## 8. Order of work

1. Frame-data-driven animation (§1) — no new assets, biggest single win.
2. Hit-stop (§2) — needs the hit event out of the controller.
3. Ink burst + shake + camera (§3).
4. Haptics + real settings gating (§4) — no assets needed.
5. Round flow (§5).
6. Movement detail (§6).
7. Default Normal + difficulty picker (§7).
8. Audio (§4) — blocked on the package + asset decision.

Items 1–6 touch `lib/game/**` and `lib/screens/bot_fight_screen.dart`; item 7
also touches the menu/standard screens. Item 8 touches `pubspec.yaml` and
`assets/**`. Whichever agent takes this, the diff is one screen and one game
file — worth doing in one batch rather than piecemeal.
