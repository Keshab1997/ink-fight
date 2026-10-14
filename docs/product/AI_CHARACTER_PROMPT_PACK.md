# AI Character and Animation Prompt Pack

## How to use this document

Generate the two base reference images first. After a base image is approved, provide it as the image reference for every frame prompt for that character. Generate **one standalone frame per call**; never ask the image model for a sprite sheet, collage, grid, turnaround, or several poses in one image.

The prompts below are written for an image model that can accept a reference image. Replace `[CHARACTER_REFERENCE]` with the approved player or bot image and replace the action line with the requested frame.

## 1. Global style lock

Use this style language in every call:

```text
Original premium mostly black-and-white doodle fighting game art for INK FIGHT: Doodle Combat. Thick confident black ink outer contour, lighter hand-drawn construction marks, controlled paper-white fill, a few soft grey ink textures, and a very limited crimson red identity accent only when specified. Expressive readable silhouette, clean isolated full-body character, consistent proportions, consistent face, consistent hands and feet, front three-quarter mobile fighting-game reference, no uncontrolled colour, no text, no logo, no UI, no background, no ground shadow, no watermark, no extra character, do not crop any part of the character.
```

## 2. Base reference prompt — player

```text
Create one standalone full-body character reference for an original mobile fighting game. The character is a friendly but determined doodle ink fighter named player_ink_fighter: white paper-toned body, thick black ink outline, oversized simple fighting gloves, small black ink scarf or wrist wrap, expressive face, light athletic silhouette, stable feet, three-quarter stance facing right. Use the global style lock. Isolate the entire character on a transparent or pure white background with generous padding. Show one neutral ready stance only. No second character, no arena, no text, no UI, no watermark, and no cropped hands or feet.
```

## 3. Base reference prompt — bot

```text
Create one standalone full-body character reference for an original mobile fighting game. The character is a stylish non-robot doodle rival named bot_crimson_rival: predominantly solid black ink body and clothing, thick expressive outline, same boxer family and proportions as the player, a sharper confident expression, white eyes inside a controlled crimson red mask-like face accent, black scarf, and a few thin crimson red contour marks on gloves and silhouette. No mechanical parts, armor panels, antenna, or robot details. Three-quarter stance facing left. Use the global style lock. Isolate the entire character on a transparent or pure white background with generous padding. Show one neutral ready stance only. No second character, no arena, no text, no UI, no watermark, and no cropped hands or feet.
```

## 4. Universal frame prompt template

```text
Using [CHARACTER_REFERENCE] as the exact character reference, create one standalone full-body animation frame of the same original doodle fighter. Preserve the exact head shape, face, body proportions, hand design, foot design, outline weight, monochrome palette, facing direction, and accessory details from the reference. The requested animation frame is: [ACTION_DESCRIPTION]. Keep the feet aligned to an invisible common baseline near the bottom of the canvas, keep the entire silhouette inside the frame with transparent or pure white background, and leave clean padding around it. This is one frame only, not a sheet or collage. No text, no UI, no arena, no ground shadow, no watermark, no other character, no colour, and do not crop any body part.
```

## 5. MVP frame prompts

The following action descriptions are appended one at a time to the universal frame prompt.

### Idle — 4 frames

- `idle_000`: neutral ready stance, knees relaxed, arms lowered but ready, calm focused face.
- `idle_001`: same stance with a tiny chest rise and scarf or ink ribbon lifted a few millimetres.
- `idle_002`: same stance with the opposite foot and shoulder carrying a very small amount of weight.
- `idle_003`: return to the exact neutral ready stance, matching frame 000.

### Walk — 6 frames

- `walk_000`: left leg beginning forward, opposite arm counter-swing, head height unchanged.
- `walk_001`: front foot extended, back heel lifting, readable balanced silhouette.
- `walk_002`: passing pose with feet close, shoulders relaxed.
- `walk_003`: opposite leg forward, mirror the weight shift without changing the face.
- `walk_004`: opposite front foot extended, back heel lifting.
- `walk_005`: passing pose returning toward the ready stance.

### Jump — 5 frames

- `jump_000`: compact crouch before takeoff, feet still on baseline.
- `jump_001`: takeoff with knees bending and fists raised, clear upward energy.
- `jump_002`: airborne apex, knees tucked slightly, full silhouette readable.
- `jump_003`: falling pose with legs preparing for landing.
- `jump_004`: grounded landing with a small ink impact mark, feet back on baseline.

### Light punch — 5 frames

- `light_punch_000`: ready stance and clear shoulder wind-up, punching arm still bent.
- `light_punch_001`: fist moving forward, elbow and face still visible.
- `light_punch_002`: crisp full extension contact frame, readable fist and short ink motion trail.
- `light_punch_003`: fist retracting, body returning from the impact.
- `light_punch_004`: exact ready stance recovery, feet on baseline.

### Heavy kick — 6 frames

- `heavy_kick_000`: low stance with clear wind-up, kicking knee beginning to rise.
- `heavy_kick_001`: knee high, torso leaning slightly, face visible.
- `heavy_kick_002`: leg extending with a strong diagonal silhouette and controlled ink trail.
- `heavy_kick_003`: full extension contact frame, body and face still readable.
- `heavy_kick_004`: leg retracting, arms balancing the motion.
- `heavy_kick_005`: exact ready stance recovery, feet on baseline.

### Block — 4 frames

- `block_000`: hands beginning to rise in front of face and torso.
- `block_001`: complete guard pose with elbows tucked and feet stable.
- `block_002`: guard absorbing an impact, small black-and-white impact mark beside the guard.
- `block_003`: guard lowering back toward ready stance.

### Hurt — 3 frames

- `hurt_000`: small recoil from an incoming hit, face surprised but still recognisable.
- `hurt_001`: strongest readable stagger, torso leaning away from the hit direction, feet visible.
- `hurt_002`: recovering toward the ready stance without changing proportions.

### Knockdown — 5 frames

- `knockdown_000`: hit launch, both feet leaving the baseline, silhouette controlled.
- `knockdown_001`: falling backward or sideways, limbs readable.
- `knockdown_002`: ground contact pose with a restrained ink impact mark.
- `knockdown_003`: one knee and one hand preparing to rise.
- `knockdown_004`: standing recovery pose, matching the ready stance.

### Victory — 5 frames

- `victory_000`: upright celebration start, fists raised, happy determined face.
- `victory_001`: full celebratory pose with scarf or ink ribbon moving upward.
- `victory_002`: strongest victory silhouette, one foot lifted or a confident lean.
- `victory_003`: settling pose with a small ink flourish.
- `victory_004`: clean result pose, feet stable and face clearly visible.

### Defeat — 5 frames

- `defeat_000`: tired stagger, shoulders lowered but face recognisable.
- `defeat_001`: knees beginning to bend, hands lowered.
- `defeat_002`: kneeling or low defeated pose, full silhouette visible.
- `defeat_003`: quiet recovery motion, no violent or graphic detail.
- `defeat_004`: final defeated result pose, suitable for a general mobile game.

## 6. Negative constraints

Append this when the model supports a negative prompt or include it in the main prompt:

```text
Avoid: multiple characters, duplicate limbs, extra fingers, missing hands, missing feet, cropped body, different face, different costume, different proportions, realistic photography, 3D render, glossy colour, complex background, arena, floor shadow, text, logo, watermark, UI, sprite sheet, contact sheet, grid, collage, turnaround, random weapon, blood, gore, copyrighted character, or artist imitation.
```

## 7. Production sequence

1. Generate player base reference.
2. Generate bot rival base reference.
3. Review silhouette, face, accessories, direction, and commercial-use suitability.
4. Lock the approved references; do not keep changing the base design during frame generation.
5. Generate MVP frames one by one using the appropriate reference image.
6. Remove accidental backgrounds and clean outline defects.
7. Align every frame to the shared baseline and pivot.
8. Name files using the convention in `CHARACTER_ART_BIBLE.md`.
9. Preview animations in Flame before generating optional polish frames.
10. Keep generation prompt, reference image, model/provider, date, and cleanup notes with the asset record.

## 8. Commercial-use safety

The final team must verify that the image provider and account plan allow commercial game use. Do not request an imitation of a living artist or a known game character. Keep the approved prompt and asset provenance record so the studio can answer questions about the artwork later.
