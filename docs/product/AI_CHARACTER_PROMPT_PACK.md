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

### Idle — 6 frames (4 keyframes + 2 in-betweens)

- `idle_000`: neutral ready stance, knees relaxed, arms lowered but ready, calm focused face.
- `idle_001`: same stance with a tiny chest rise and scarf or ink ribbon lifted a few millimetres.
- `idle_002`: same stance with the opposite foot and shoulder carrying a very small amount of weight.
- `idle_003` — **in-between (002 → 004)**: idle in-between with the same ready stance, face, gloves and feet as both neighbouring frames and the body in exactly the same place on the canvas; only the black scarf moves: medium-length tails lifting behind his neck, their tips ending level with the outer edge of the rear glove, clearly shorter than the long trailing tail of the frame after, and nothing reaching further left than the rear glove.
- `idle_004`: return to the exact neutral ready stance, matching frame 000.
- `idle_005` — **in-between, loop seam (004 → 000)**: idle loop-seam in-between with the same ready stance, face, gloves and feet as both neighbouring frames; the long black scarf tail falls back halfway toward the short resting flick of frame 000, with a tiny exhale in the chest, so the idle loop closes without a pop.

Both fighters have all six. For the player, the `idle_003` prompt sends the
scarf tail out horizontally to the left at shoulder height, never above the
shoulders. The delivered one is a touch longer than frame 004's, which reads as
the scarf flicking out and settling. It is foot-registered (§5b), so the body
does not move.

### Walk — 8 frames (6 keyframes + 2 in-betweens, one per half-stride)

- `walk_000`: left leg beginning forward, opposite arm counter-swing, head height unchanged.
- `walk_001`: front foot extended, back heel lifting, readable balanced silhouette.
- `walk_002` — **in-between (001 → 003)**: walk in-between, the front foot flattening onto the ground and taking the weight, the back foot peeling off the ground and starting to swing forward under the hips, the feet about halfway between their spread in the frame before and in the frame after; head height unchanged, gloves halfway between their positions in the two neighbouring frames.
- `walk_003`: passing pose with feet close, shoulders relaxed.
- `walk_004`: opposite leg forward, mirror the weight shift without changing the face.
- `walk_005`: opposite front foot extended, back heel lifting.
- `walk_006` — **in-between (005 → 007)**: walk in-between on the opposite leg, the extended front foot flattening and taking the weight, the back foot lifting and swinging forward under the hips (the rival's knee starting to bend forward), the feet closing halfway toward the passing pose of the frame after; head height unchanged, the gloves rising halfway toward the guard of the frame after.
- `walk_007`: passing pose returning toward the ready stance.

One in-between in each half-stride, at the same place, so both halves of the
cycle keep the same number of frames. Uneven halves would make one step
slower than the other while the body moves at a constant speed.

### Jump — 5 frames

- `jump_000`: compact crouch before takeoff, feet still on baseline.
- `jump_001`: takeoff with knees bending and fists raised, clear upward energy.
- `jump_002`: airborne apex, knees tucked slightly, full silhouette readable.
- `jump_003`: falling pose with legs preparing for landing.
- `jump_004`: grounded landing with a small ink impact mark, feet back on baseline.

### Light punch — 7 frames (5 keyframes + 2 in-betweens)

- `light_punch_000`: ready stance and clear shoulder wind-up, punching arm still bent.
- `light_punch_001` — **in-between (000 → 002)**: light punch in-between, launching the jab: the punching front glove halfway along its path from the cocked wind-up to the straight-arm extension, the elbow bent at a right angle and the glove level with the chin, only halfway to full reach and clearly shorter than the straight arm of the frame after; shoulder turning into the punch; the rear glove guarding the chest; feet planted exactly as in both neighbours.
- `light_punch_002`: fist moving forward, elbow and face still visible.
- `light_punch_003`: crisp full extension contact frame, readable fist and short ink motion trail.
- `light_punch_004`: fist retracting, body returning from the impact.
- `light_punch_005` — **in-between (004 → 006)**: light punch in-between, recovering: the punching glove pulled back the last stretch toward the raised guard beside the face, elbow tucking in, shoulders squaring back toward the ready stance (the rival's rear glove dropping halfway toward the hip); feet planted exactly as in both neighbours.
- `light_punch_006`: exact ready stance recovery, feet on baseline.

The contact pose is now frame 003, and the recipe in GAME_FEEL §1 keeps it on
screen for exactly the 90–160 ms active window. A launch drawn at full
extension was rejected: the longer arm widens the bounding box, so the body
flickered 44 px backwards for one frame.

### Heavy kick — 8 frames

- `heavy_kick_000`: low stance with clear wind-up, kicking knee beginning to rise.
- `heavy_kick_001`: knee high, torso leaning slightly, face visible.
- `heavy_kick_002` (in-between, §5b): the kick unfolding. The knee is at chest height and points right, the shin swings out toward horizontal so the foot is at hip height in front of him (leg half extended, knee at roughly 120°), the supporting leg straightens and the torso starts to lean back; front glove at the chin, rear glove low. No swoosh. The player's is foot-registered (§5b).
- `heavy_kick_003`: leg extending with a strong diagonal silhouette and controlled ink trail.
- `heavy_kick_004`: full extension contact frame, body and face still readable.
- `heavy_kick_005` (in-between, §5b): straight after contact. The kicking leg folds back at the knee, the foot still high but the shin coming in; the torso rises back upright and the arms balance in guard. No swoosh, no impact burst.
- `heavy_kick_006`: leg retracting, arms balancing the motion.
- `heavy_kick_007`: exact ready stance recovery, feet on baseline.

### Block — 6 frames (raise 000–001 · held loop 002–003 · release 004–005)

- `block_000` (in-between, §5b): the guard rising. Both gloves are halfway up from the ready stance toward the high guard, at chin height, forearms coming up in front of the chest, elbows tucked; same planted feet and stance as idle. No impact spark. Its neighbours are `idle_000` and `block_001`.
- `block_001`: hands rising in front of face and torso (as delivered, this is already almost the complete guard).
- `block_002`: complete guard pose with elbows tucked and feet stable.
- `block_003`: guard absorbing an impact, small black-and-white impact mark beside the guard.
- `block_004` (in-between, §5b): the guard starting to lower. Both gloves are halfway down from the high guard toward the lowered guard, at chin height, elbows tucked; same planted feet. No impact spark, no burst. It is foot-registered (§5b), because the spark on `block_003` widens that frame's box.
- `block_005`: guard lowering back toward ready stance.

### Hurt — 5 frames

- `hurt_000`: small recoil from an incoming hit, face surprised but still recognisable.
- `hurt_001` (in-between, §5b): the recoil building. The head snaps back, the torso starts tilting away from the hit (toward the left; he still faces right), the front glove starts to fly up and the front heel lifts while both feet stay near the ground. The face is halfway from surprised to pained. No stars, no impact marks.
- `hurt_002`: strongest readable stagger, torso leaning away from the hit direction, feet visible. The rival's has small dizzy stars; this is the only frame that does.
- `hurt_003` (in-between, §5b): coming back from the stagger. The torso is halfway back to upright, the lifted foot comes back down, the feet draw back under the body and both arms return toward guard. The face is halfway from pained to determined. No stars.
- `hurt_004`: recovering toward the ready stance without changing proportions. It holds until the hitstun ends.

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

### Hurt heavy — 6 frames (knockback that travels) — `hurt_heavy`

Added after playtesting feedback that a hit does not read as one: the fight had
a single 3-frame `hurt` cycle for every hit, so a jab and a heavy kick looked
identical and nothing showed the player being *driven backward*. The art bible
already reserved this animation under the name `hit_heavy` (online polish set);
this is it, promoted because the feel needs it now.

Both characters are drawn **facing RIGHT**, so "knocked backward" means the body
is thrown toward the **LEFT** of the canvas while the opponent stands to the
right. The cycle must read as movement across these four frames, not as four
poses: the arms and the head lead, the feet catch up.

- `hurt_heavy_000` — impact: head snapped back with the chin tucked, both fists blown up and out of the guard, weight already travelling backward.
- `hurt_heavy_001` (in-between, §5b) — straightening out of the impact into the recoil. The torso passes through upright on its way from folded forward (000) to arched back (002). Both boxing gloves are thrown up above the shoulders, the head tilts back with the eyes squeezed shut and the mouth open in pain, and the feet are still near their impact positions. Say "boxing gloves, never open hands": one attempt drew bare hands.
- `hurt_heavy_002` — maximum recoil: torso furthest back, front foot sliding backward, back knee bent deep under the force, scarf whipped forward past the face.
- `hurt_heavy_003` (in-between, §5b) — coming out of the deepest recoil into the skid. The torso leans back less than in 002, both feet are planted and spread nearly as wide as in the skid, knees bent, both arms flail out at shoulder height, and the head comes back up, the face pained turning worried. No ground line, splashes or dust (the skid frame has its own).
- `hurt_heavy_004` — the skid: feet planted wide apart mid-slide, body still leaning back, both arms flailing outward to catch balance, face coming back up.
- `hurt_heavy_005` — recovering: centred again with weight settling, arms returning toward guard. This is the frame the player sees when control comes back, so it must read as ready, not as a second stagger.

Append to the universal frame prompt (section 4) for every one of the four:

```text
The character still faces RIGHT exactly as in the reference — his face and both fists point toward the right side of the canvas, and the blow is driving him toward the left of the canvas. Do not mirror, flip or turn the character. Both feet stay on the ground: this is a ground slide, never a launch into the air. No dizzy stars, no asterisks, no sparkles, no impact marks and no motion lines around the head — the game draws its own hit effects on top of these frames.
```

**Facing lock (learned the hard way).** A first demo of this cycle came back
with the rival's crimson mask on the *left* of his head — the whole character
mirrored — even though the prompt said "faces RIGHT, hit from the right". It is
an easy mistake for an otherwise good recoil pose, so it is checked, not
trusted: for the bot, measure the crimson accent centroid against the drawing's
centre; for the player, look at which side the face and the leading fist are on.
A mirrored frame is unusable — in-game the rival is mirrored again to face the
player, and a flipped frame leaves him punching backwards.

**Known mirrored keyframe.** `bot_crimson_rival_heavy_kick_004` (the contact
frame; it was `_003` before the in-betweens) fails this check: the kick, the
impact burst and the scarf all point the wrong way, so in-game the rival kicks
away from the player for the 90 ms active window. Not fixed yet (regenerate it
facing right). Until then, an in-between next to it uses a horizontally flipped
copy as its neighbour reference, as the rival's `heavy_kick_005` did.

## 5b. In-between frames — densifying the delivered cycles

Thin cycles read choppy, so the delivered cycles get in-between frames. An
in-between is generated like any other frame (one image per call, approved
reference first) with **both neighbouring keyframes as extra image inputs**:
image 1 is the reference, image 2 the frame before, image 3 the frame after.
Append this to the universal frame prompt (section 4), plus the
character-specific face lock:

```text
The second image is the animation frame immediately BEFORE the requested frame and the third image is the frame immediately AFTER it. The requested frame is the in-between that sits exactly halfway between those two frames: copy their scale, framing, outline weight, face and ground baseline exactly, and change only what moves between them. The character faces RIGHT exactly as in the reference; do not mirror, flip or turn the character. No motion lines, no speed lines, no swoosh marks, no ink trails, no splashes.
```

- Player face lock: *the same angry slanted black eyebrows, the same eyes and
  the same confident smirk* (a first attempt that skipped this lost the brows).
- Rival face lock: *the same crimson mask with white eyes, the same sharp black
  hair tufts and the same small stern mouth*.
- Name the change against the neighbours ("halfway between its short flick and
  its long trailing swing") rather than describing a fresh pose.

**Acceptance gate (checked, not trusted).** Run the frame through
`tool/process_character_assets.py`'s cleanup and alignment and compare it with
both neighbours: clean border background, feet on the 900 px baseline, the
facing lock above, and the head and feet staying within about 15 px of the
neighbours' range. The tool centres each frame on its bounding box, so a scarf
drawn longer than both neighbours shifts the whole body sideways. That reads as
a twitch, which is worse than the gap the frame was meant to fill. Measure the
whole cycle before and after: the largest single-frame jump must not grow by
more than that same tolerance.

For attack and reaction cycles (punches, kicks, hurt), anchor on the planted
foot instead of the head. The head measure (the top 22 % of the figure) picks
up a raised glove or a kicking foot, while the lowest 40 rows are the foot that
carries the weight. That foot must stay within the same 15 px of the
neighbours' range, and its largest step must not grow beyond that tolerance.
The head may travel, because in a kick or a recoil it really does.

**Foot registration (when centring is the problem, not the drawing).** A frame's
planted foot lands at 512 + (foot − box centre) × scale, so a pose whose box
differs from its neighbours' gets slid sideways, however well it is drawn. That
happens with a half-extended kick next to a crouch the tool scales up, a scarf a
little longer than the next frame's, or a neighbour widened by an impact spark.
Such frames are listed in `FOOT_REGISTERED` in `tool/process_character_assets.py`
together with their two neighbours. After alignment, the tool shifts each one
sideways so that its planted foot (the lowest 40 rows) lands halfway between
theirs. The art stays untouched AI output, and every unlisted frame stays
byte-identical. A frame is listed only when plain centring puts its foot clearly
outside the gate, and only if registration does not make its total silhouette
change against the two neighbours materially worse (by more than 0.05).
Otherwise it keeps plain centring.

What the gate measured on the frames that landed (largest head jump per frame
step / mean silhouette change, before → after):

| Cycle | player | rival |
|---|---|---|
| idle | 13 px / 0.11 → 12 px / 0.08 (seam + 002 → 003, registered) | 43 px / 0.23 → 29 px / 0.18 |
| walk | 8 px / 0.18 → 8 px / 0.15 | 40 px / 0.25 → 42 px / 0.22 |
| light punch | 86 px / 0.28 → 52 px / 0.29 | 35 px / 0.25 → 42 px / 0.22 |
| hurt | 56 px / 0.68 → 72 px / 0.52 ¹ | 14 px / 0.33 → 49 px / 0.26 ¹ |
| heavy kick | 177 px / 0.44 → 216 px / 0.45 ² | 155 px / 0.36 → 155 px / 0.32 ³ |
| hurt heavy | 219 px / 0.59 → 181 px / 0.55 | 178 px / 0.50 → 96 px / 0.43 ⁵ |
| block raise ⁴ | 33 px / 0.23 → 23 px / 0.18 | 0 px / 0.08 → 0 px / 0.05 |
| block release ⁴ | 18 px / 0.26 → 27 px / 0.21 | 42 px / 0.27 → 29 px / 0.22 |

¹ Here the head measure includes the gloves thrown up by the hit. The planted
feet stay inside the old frames' spread on every frame; the rival's stay within
±10 px on all five. So the head number is not body travel.

² Judge this by the planted foot: its largest step halves, from 108 to 55 px
(with `heavy_kick_002` foot-registered; plain centring would have put it at
173 px). The silhouette mean does not move. Delivered frames 000 and 001 are
identical, and registering 002 trades 0.57 + 0.57 against its neighbours for
0.67 + 0.50. The head measure picks up the kicking leg.
³ Both largest steps are the jump into and out of the mirrored contact keyframe
(above). The in-betweens do not change it.
⁴ Measured from `idle_000` through the raise to the first held frame, and from
the last held frame through the release back to `idle_000`. The rival's raise
in-between moves the gloves inside his outline, so the silhouette barely sees
it (0.01 to `block_001`). Its colour difference is in between, though: idle to
guard 53.8, idle to the new frame 42.6, the new frame to the guard 20.2.
⁵ The rival's largest planted-foot step grows from 162 to 180 px. Its 001 lands
18 px past its neighbours' range, 3 px over the tolerance, and is accepted with
that note. Registering it would have worsened its silhouette change against the
two neighbours from 0.87 to 1.26.

Rejected, with the measurement: the player's idle 002 → 003 in-between, four
attempts. Twice the scarf came out longer than in frame 003 (the largest head
jump of the loop grew from 13 px to 39 px), once it rose straight up, and once
the eyebrows were missing. The rival's version passed only on its third attempt,
once the prompt fixed the scarf length explicitly ("tips ending level with the
outer edge of the rear glove"). Fix lengths and directions explicitly like
that; "halfway" alone is not enough.

A fifth attempt at that frame drew the scarf horizontal as asked, but again
longer than frame 003 (head jump 13 → 42 px). The player's heavy-kick unfolding
in-between failed once outright: it returned frame 001 unchanged (silhouette
distance 0.00). Name the pose's geometry and say "not a copy of either input".
The second attempt drew the right pose, but plain centring put its planted foot
96 px past the extension frame's (foot path 299 → 472 → 376 px), a
forward-and-back lurch in the wind-up. That is the case foot registration
exists for, and it is the frame that landed. So is the fifth idle attempt:
registered, its body stays put (the loop's largest head step is 12 px) and the
slightly long scarf reads as a flick.

Heavy hurt: the player's impact → recoil in-between took five attempts.
- The first came out with its foot 38 px and its head 29 px outside the
  neighbours' range. I first blamed its upright torso, which was wrong: 000 folds
  forward and the recoil arches back, so the swing passes through upright, and
  the frame that landed is upright too.
- The second turned the boxing gloves into open hands, which is off-model.
- Of the last two, one hid the face behind the gloves; the other is the frame
  that landed.

The first recoil → skid attempt was the recoil frame with a new face and a
ground line (silhouette distance 0.10). The rival's impact → recoil in-between
passed first time. It waited one batch for the player's, because the recipe is
shared.

**Haze.** A generation can leave a faint grey ground smudge under a lifted foot
(the rival's `walk_002` did). `tool/process_character_assets.py` now clears any
light-grey blob that is detached from the character. The original keeps the
smudge, and no hand-cleaned frame changes: every existing runtime frame came out
byte-identical.

**Provenance.** Generated 2026-10-15 with `gemini-3.1-flash-image` through the
agent's image tool, from `player_ink_fighter/reference_clean_source.png` and
`bot_crimson_rival/reference_raw_black.png` (the references the delivered
frames match), plus the two neighbouring originals. The originals are archived
untouched: no cleanup or editing before `tool/process_character_assets.py`.

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
