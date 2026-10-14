# Character Asset Pipeline

## Goal

Turn AI-generated doodle references into reliable, lightweight Flame assets without sacrificing consistency or the premium black-and-white identity.

## Directory layout

```text
assets/
  characters/
    player_ink_fighter/
      reference/
      idle/
      walk/
      jump/
      light_punch/
      heavy_kick/
      block/
      hurt/
      knockdown/
      victory/
      defeat/
    bot_ink_brawler/
      reference/
      idle/
      walk/
      jump/
      light_punch/
      heavy_kick/
      block/
      hurt/
      knockdown/
      victory/
      defeat/
```

## AI-to-game workflow

1. **Reference lock:** approve one player and one bot full-body reference.
2. **Frame generation:** create one frame per image-model call using the locked reference as an image input.
3. **Cleanup:** remove background, repair outline gaps, remove artifacts, and ensure no accidental text or watermark remains.
4. **Alignment:** place the feet on a shared baseline and set the pivot to the centre of the feet.
5. **Export:** save an RGBA PNG master, then make a runtime-sized copy.
6. **Animation test:** load the frames in a small Flame preview before generating optional polish.
7. **Atlas packing:** pack only after the individual frames pass review.
8. **Repository record:** keep prompt, reference, provider/model, date, and license check in an asset manifest. Do not commit provider tokens.

## Review gates

### Reference gate

- [ ] Player and bot are visually distinct.
- [ ] Direction and accessories are locked.
- [ ] The silhouette is readable at small size.

### Frame gate

- [ ] Same face, head, hands, feet, and body proportions.
- [ ] No cropping or extra limbs.
- [ ] Baseline and pivot match.
- [ ] Transparent background is clean.
- [ ] No colour drift, UI, text, or watermark.

### Runtime gate

- [ ] SpriteAnimation loops smoothly.
- [ ] Hit and hurt frames do not hide gameplay state.
- [ ] Debug hitbox and hurtbox remain stable.
- [ ] Memory and frame time are acceptable on low-end Android.
- [ ] Player and bot use the same state IDs for bot and online modes.

## Asset manifest fields

Every approved asset set should record:

```text
asset_id
character_id
animation_id
frame_count
canvas_size
runtime_size
pivot
baseline
provider_and_model
prompt_file
reference_file
created_at
cleanup_notes
commercial_use_review
approved_by
```

## Important scope rule

The first bot fight should start with the 48-frame MVP set per character listed in `CHARACTER_ART_BIBLE.md`. Run the game with these frames before adding run, dash, dodge, special, taunt, or extra victory animations.
