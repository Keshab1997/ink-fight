# Character Art Bible and Frame Inventory

## Document control

- **Product:** INK FIGHT: Doodle Combat
- **Art direction:** premium black-and-white doodle ink
- **Target runtime:** Flutter + Flame on landscape mobile
- **First playable target:** Player vs Bot
- **Online target:** the same assets are reused in separate-device online 1v1
- **Asset status:** design specification; reference images are generated separately

## 1. Non-negotiable art rules

1. Use only black, white, and controlled grey values. No uncontrolled colour accents.
2. Characters must have a strong silhouette that remains readable on a small landscape screen.
3. Use expressive variable-width ink lines: a heavier outside contour and lighter construction marks.
4. The player and bot must be visually distinct even when effects are disabled.
5. Keep the same head size, body proportion, hand size, foot position, and line language across every frame.
6. Do not put text, UI, arena backgrounds, watermarks, or extra characters inside a character frame.
7. Each frame is one standalone full-body image. Do not generate a contact sheet or a grid.
8. Hands, feet, weapon-free fists, face, and silhouette must be fully visible; never crop the character.
9. Keep a fixed baseline and pivot so the character does not jump while animating.
10. The art must be original. Do not imitate a living artist or use a known game, film, comic, or mascot character.

## 2. Character identities

### Player — `player_ink_fighter`

- White paper-toned body with a thick black ink outline.
- A small black ink scarf or wrist wrap for a recognisable motion accent.
- Friendly but determined face; one clear eye shape and a readable mouth.
- Light athletic doodle silhouette with oversized gloves and stable feet.
- Three-quarter fighting stance facing right in the reference image.
- White fill must remain distinct from the paper arena through its black contour.

### Bot — `bot_crimson_rival`

- Predominantly solid black ink body with controlled crimson red accents.
- Same doodle-boxer family as the player, but with sharper hair/ink tufts, a confident rival expression, and a red mask-like face mark.
- White eyes remain readable inside the crimson face accent.
- Black scarf, gloves, and clothing use a thin red contour only where it improves recognition.
- Slightly heavier stance and larger shoulders than the player, without any robot or mechanical parts.
- Three-quarter fighting stance facing left in the reference image.
- The rival should feel stylish and competitive, not frightening, gory, or over-detailed.

## 3. Frame inventory

The first production pass uses the same action vocabulary for both characters. Generate one frame at a time using the prompt pack in `AI_CHARACTER_PROMPT_PACK.md` and the approved base reference image.

### MVP Bot Fight set — per character

| Animation ID | Frames | Loop | Purpose |
|---|---:|---|---|
| `idle` | 4 | yes | breathing, small ink scarf/antenna motion |
| `walk` | 6 | yes | readable left/right movement |
| `jump` | 5 | no | takeoff, rise, apex, fall, landing |
| `light_punch` | 5 | no | wind-up, extension, contact, recoil, recovery |
| `heavy_kick` | 6 | no | wind-up, lift, extension, contact, recoil, recovery |
| `block` | 4 | no | raise guard, hold, impact, release |
| `hurt` | 3 | no | hit reaction, recoil, return |
| `knockdown` | 5 | no | launch, fall, ground contact, recovery start, stand |
| `victory` | 5 | no | celebration loop or result pose |
| `defeat` | 5 | no | stagger, kneel/fall, defeated hold, recovery, final pose |
| **Total** | **48** |  | **per character** |

**MVP total:** 96 individual frames for the player and bot together. Frames can be rendered from approved references, then cleaned and packed into atlases.

### Online polish set — later

Do not block the first bot fight on these animations:

- `run` — 6 frames
- `dash` — 5 frames
- `dodge` — 6 frames
- `special_attack` — 8 frames
- `intro` — 5 frames
- `taunt` — 5 frames
- `victory_alt_01` — 5 frames
- `victory_alt_02` — 5 frames
- `hit_heavy` — 4 frames
- `block_break` — 5 frames

Online gameplay uses the same animation IDs for both clients. The network sends state and input; it does not send image files during a match.

## 4. Frame pose rules

### Idle

The feet stay on the baseline. Use a small breathing shift and a very small scarf/antenna movement. Do not change the face or body proportions between frames.

### Walk

Keep the head height stable. Alternate feet clearly, use a small shoulder counter-motion, and keep the character facing the same direction. The walk must read at thumbnail size.

### Jump

Use a clear crouch/takeoff, compact rise, open apex, falling pose, and grounded landing. Feet may leave the baseline only during the airborne frames.

### Light punch

The contact frame must be the clearest silhouette. The fist may have a short ink trail, but the hand must remain readable. The recovery frame must return to the same baseline stance.

### Heavy kick

Use a long readable wind-up and strong extension. Do not hide the face or torso behind the leg. The bot and player may have different kick energy, but the timing vocabulary stays consistent.

### Block

The guard must be obvious without relying on colour. Add a small black-and-white impact mark only on the contact frame.

### Hurt and knockdown

Avoid extreme distortion that changes the character identity. The hit direction and recovery point should be clear for gameplay readability.

### Victory and defeat

Use expressive poses that can be read behind the result overlay. Victory must feel energetic; defeat must remain suitable for a general mobile game audience.

## 5. Export contract

- **Master frame:** PNG with RGBA transparency, 1024 x 1024 pixels.
- **Runtime frame:** export 512 x 512 first; atlas packing can reduce size later.
- **Pivot:** horizontal center of the feet; baseline at approximately 88% of the canvas height.
- **Padding:** at least 8% transparent breathing room around the silhouette.
- **Direction:** player reference faces right; bot reference faces left. Do not flip frames without checking facial details.
- **Colour:** black `#101010`, paper white `#F7F7F2`, and a controlled rival crimson accent `#C51F3A`; grey only for controlled texture.
- **Naming:** `{character}_{animation}_{frame:000}.png`.

Examples:

```text
player_ink_fighter_idle_000.png
player_ink_fighter_light_punch_002.png
bot_crimson_rival_block_001.png
bot_crimson_rival_defeat_004.png
```

## 6. Flame integration plan

1. Store approved frames under `assets/characters/<character>/<animation>/`.
2. Declare the asset directories in `pubspec.yaml`.
3. Pack frames into `SpriteAnimation` objects with explicit step times.
4. Keep the fighter's world anchor at the feet, not the image centre.
5. Use the same animation IDs in bot and online match state machines.
6. Add a debug toggle that draws the sprite bounds, pivot, baseline, hitbox, and hurtbox.
7. Test the smallest frame and the largest frame side-by-side before adding particles.

## 7. Acceptance checklist

- [ ] Both base references approved.
- [ ] Player and bot remain identifiable in every frame.
- [ ] No frame contains text, UI, watermark, background, or another character.
- [ ] Baseline and pivot remain stable.
- [ ] All frames are RGBA PNGs with no accidental white rectangle.
- [ ] The character reads at the smallest planned phone render size.
- [ ] Animation loops do not visibly pop.
- [ ] Frame naming and folders match the export contract.
- [ ] Commercial-use and generation records are stored with the project.
