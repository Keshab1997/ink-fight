# Game Design Document

## Document control

- **Product:** INK FIGHT: Doodle Combat
- **Package:** `com.keshabstudios.inkfight`
- **Version:** 0.1 pre-production
- **Last updated:** 2026-10-14
- **Owner:** Keshab Studios
- **Orientation:** Landscape only

## 1. High concept

INK FIGHT is a premium-feeling 2D doodle fighting game for mobile. A player controls an expressive ink fighter in short, readable matches. The first release is Player vs Bot. A later release adds online 1v1 matches on separate devices; same-device two-player mode is intentionally out of scope.

**One-line pitch:** *Draw. Fight. Dominate.*

## 2. Product goals

- Make the first fight understandable in under one minute.
- Make every hit feel physical through animation, sound, hit-stop, particles, and haptics.
- Make the black-and-white art direction recognisable from the app icon and screenshots.
- Build combat rules that can be simulated locally first and later run with a server-authoritative online match.
- Monetise without interrupting combat or selling competitive power.

## 3. Non-goals for the first release

- Same-device local multiplayer.
- A large roster of fighters.
- Ranked online play before casual online matches are stable.
- Live voice chat.
- Loot boxes, energy timers, pay-to-win upgrades, or intrusive full-screen ads during combat.
- A complex open-world progression system.

## 4. Target experience

The intended match is short, focused, and replayable. The player should see a clean landscape arena, instantly understand both health bars, recognise attack wind-ups, and know why a hit landed or missed. A match should usually last approximately 60–120 seconds, with a clear result and a fast rematch option.

## 5. Game flow

1. **Splash** — logo animation, asset preloading, network status if needed.
2. **Main Menu** — Bot Fight is the primary call to action; Online 1v1 is labelled coming soon or unlocked when available.
3. **Character Select** — choose an available fighter and view simple move hints. Locked content is cosmetic or clearly marked as future content.
4. **Match Intro** — fighter names, arena title, and a short countdown.
5. **Fight Arena** — movement, attacks, block, jump/dodge, health, timer, pause/report access.
6. **Result** — victory/defeat, score, earned cosmetic currency if implemented, rematch, and return to menu.
7. **Online lobby later** — quick match, room state, ready state, reconnect, result confirmation, rematch.

## 6. Match rules

### Bot Fight MVP

- One round.
- 60-second match timer, tunable after playtesting.
- Victory when the opponent's health reaches zero.
- If time expires, the fighter with more health wins; a tie is a draw.
- Rematch reloads the same arena without forcing the player through all menus.
- Difficulty presets: Easy, Normal, and Hard. Normal is the default.

### Online 1v1 initial version

- Two players on separate devices.
- Casual matchmaking first; ranked mode only after network quality, disconnect handling, and abuse reporting are proven.
- Both clients display a consistent local-player view, with the opponent clearly identified.
- The authoritative match result comes from the game server, not from a client-only claim.
- A rematch request is mutual and time-limited.

## 7. Core combat

### Player actions

- Move left/right.
- Jump.
- Light attack: quick, low commitment, low damage.
- Heavy attack: slower, readable wind-up, higher damage or knockback.
- Block: reduces or negates selected incoming damage; stamina or timing rules can be tuned later.
- Dodge or dash: optional for the first vertical slice; add only when the base controls are reliable.

### Combat states

`Idle → Move → Attack startup → Active hitbox → Recovery → Hitstun / Blockstun → Knockdown → Recover`

Every action must have a readable animation cue and a predictable recovery window. Hitboxes and hurtboxes must be debug-renderable during development.

### Feel targets

- Small hit-stop on confirmed hits.
- Distinct light and heavy impact sounds.
- Ink burst, line shake, and a brief camera response on strong attacks.
- Haptic feedback that can be disabled.
- No visual effect should hide the fighters or health state.

## 8. Bot design

The bot is a fair practice opponent, not a cheating opponent. It must use the same movement and combat rules as the player.

- **Easy:** slower reaction, fewer attacks, visible openings.
- **Normal:** blocks occasionally, approaches, attacks after a readable cue, respects cooldowns.
- **Hard:** better timing and spacing, but still has recoveries and exploitable patterns.
- Difficulty must not secretly multiply health or damage without clearly communicating the rule.

## 9. Progression and cosmetics

Progression should reward play without changing competitive power.

Possible unlocks:

- Ink colour accents that preserve the monochrome identity.
- Victory poses.
- Paper/arena backgrounds.
- Fighter gloves, masks, or line styles.
- Profile badges and non-competitive titles.

Do not sell damage, speed, health, hitbox size, or matchmaking priority.

## 10. Art direction

- Strict black, white, and controlled grey values; no uncontrolled colour drift.
- Thick expressive silhouettes readable on small screens.
- Paper grain, pencil construction marks, and ink splashes used with restraint.
- UI uses generous spacing, high contrast, large touch targets, and one strong type hierarchy.
- Transitions should feel like ink strokes being drawn, erased, or stamped.

## 11. Audio direction

- Short tactile impacts rather than noisy continuous effects.
- Distinct cues for countdown, low health, block, victory, defeat, and connection state.
- Music should support focus and duck during important combat sounds.
- All audio and haptics require independent settings.

## 12. Monetisation

AdMob may be used after the core loop is stable.

- Optional rewarded ad: bonus cosmetic currency or a clearly described post-match reward.
- Limited interstitial: only at a natural result/menu transition, never in active combat.
- No ad should be required to continue a match.
- No pay-to-win items.
- Consent and privacy configuration must be implemented before production ads.

See `ADS_AND_REWARDS.md` and the legal drafts before integrating the SDK.

## 13. Accessibility

- High-contrast mode remains the default, not an afterthought.
- Haptics can be disabled.
- Music, effects, and UI volume are separate.
- Touch targets should meet platform accessibility guidance.
- Avoid communicating essential information only through colour.
- Connection and result states must be visible and text-labelled.

## 14. Analytics and privacy

Only collect events needed to improve reliability and understand game health. Proposed events include match start/end, bot difficulty, tutorial completion, crash/ANR diagnostics, ad opt-in/result, and online connection outcome. Do not log message contents, authentication tokens, or unnecessary personal data. The actual event list must match the final privacy policy and data safety form.

## 15. Definition of a premium vertical slice

The first playable slice is ready for a small playtest when:

- All screens are landscape and safe-area aware.
- One fighter can move, jump, attack, block, take damage, and recover.
- The bot uses the same rules and cannot deal impossible damage.
- Health, timer, pause, result, and rematch states are clear.
- Input feels responsive on at least low-end and mid-range test devices.
- There are no ads in the test build.
- A clean restart works after win, loss, pause, and app backgrounding.
- No known crash occurs in the documented test path.
