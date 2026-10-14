# Controls and Tutorial Specification

## Orientation and layout

INK FIGHT is landscape-only. The layout must work across common 16:9, 18:9, and 20:9 phone aspect ratios without covering the system safe areas.

- Keep the arena and fighters in the visual centre.
- Keep the top HUD away from cutouts and rounded corners.
- Keep the movement control in the lower-left safe area.
- Keep action buttons in the lower-right safe area.
- Use large targets with a visible pressed state and a short input buffer.

## Proposed control map

| Control | Default action | Feedback |
|---|---|---|
| Movement pad | Walk left/right; optional crouch direction later | Fighter turns and footstep cue |
| Attack | Fast light attack | Small ink hit effect |
| Heavy/Kick | Slower stronger attack | Larger wind-up and impact |
| Block | Reduce or negate selected damage | Guard pose and block sound |
| Jump/Dodge | Jump in the vertical slice; dodge later if needed | Clear arc or dash trail |
| Pause | Pause bot match; online uses a limited menu | Overlay with settings and exit rules |

Do not ship a control that looks tappable but does not respond. Every action needs a pressed, cooldown, or unavailable state.

## First-time tutorial script

1. **Welcome:** “Welcome to the ink arena.”
2. **Move:** “Drag the left control to move.”
3. **Attack:** “Tap Attack when you are in range.”
4. **Block:** “Hold Block to defend against a readable attack.”
5. **Heavy:** “Heavy attacks are stronger, but slower.”
6. **Read the opponent:** “Watch the wind-up. Good timing beats button mashing.”
7. **Win condition:** “Reduce the opponent’s health before the timer ends.”
8. **Practice finish:** “Ready? Draw your line.”

The tutorial should be skippable, replayable from Settings, and never force a rewarded ad.

## Combat readability checklist

- Attack startup is visible before the hitbox becomes active.
- Strong attacks use a distinct sound and animation.
- Blocking is not communicated by colour alone.
- Hitboxes can be visualised in a development-only debug mode.
- The camera never hides a fighter behind an effect.
- Low health has a subtle text/icon warning as well as a visual cue.
- Online connection loss is a clear state, not a frozen animation.

## Accessibility checklist

- Haptics, music, and effects are separate toggles.
- Button opacity and scale are configurable if playtesting shows a need.
- Essential information remains readable in grayscale.
- Do not place two important buttons so close that accidental taps are likely.
- Use labels or icons with a tutorial explanation; icons alone must not be ambiguous.
