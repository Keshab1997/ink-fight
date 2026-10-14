# INK FIGHT: Doodle Combat

**INK FIGHT** is a premium black-and-white doodle fighting game designed for landscape mobile play. The first release focuses on a polished Player vs Bot experience; online 1v1 matchmaking is the next major mode.

> **Project status:** Flutter foundation / first playable shell. The repository contains the product specification, player-facing rules, legal drafts, technical plan, visual concepts, and the first polished landscape home screen. The Bot Fight arena is the next implementation slice.

## Product identity

| Item | Decision |
|---|---|
| Game title | **INK FIGHT: Doodle Combat** |
| Android application ID | `com.keshabstudios.inkfight` |
| Studio | Keshab Studios |
| Orientation | Landscape only |
| Visual direction | Premium monochrome ink, paper texture, expressive doodle fighters |
| Initial mode | Player vs Bot |
| Planned competitive mode | Online 1v1 on separate devices |
| Local same-device multiplayer | Not planned |
| Monetisation | AdMob with optional rewarded ads and carefully limited interstitials |

## Core promise

Every match should feel like a clean ink sketch brought to life: quick to understand, satisfying to control, readable on a phone, and fair enough that skill matters more than spending.

## Design pillars

1. **Readable combat** — clear silhouettes, telegraphed attacks, readable hit feedback, and a reliable HUD.
2. **Premium restraint** — no ads during a fight, no pay-to-win stats, fast screens, and purposeful motion.
3. **Doodle personality** — hand-drawn animation, ink splashes, paper grain, and expressive reactions.
4. **Fair online play** — server-authoritative match results, reconnect handling, anti-cheat planning, and respectful community rules.
5. **Small vertical slice first** — ship one excellent bot arena before expanding characters, arenas, and online systems.

## Planned player flow

```text
Splash Screen
    ↓
Main Menu
    ↓
Bot Fight
    ↓
Character Select
    ↓
Fight Arena
    ↓
Win / Lose Screen
    ↓
Rematch or Main Menu
    ↓
Online 1v1 Arena unlocks in a later release
```

## Repository map

- `docs/product/` — game design, player guide, controls, rules, community documents, and the character art/prompt pack.
- `docs/technical/` — architecture, backend plan, roadmap, and release checklist.
- `docs/legal/` — drafts that must be completed and legally reviewed before public launch.
- `docs/concepts/` — selected visual references for the landscape UI direction.

## Quality bar

The game should target a stable 60 FPS on supported devices, responsive touch input, strong contrast, short loading times, and consistent landscape layouts. Audio, haptics, hit-stop, transitions, and accessibility are part of the product—not afterthoughts.

## Monetisation principles

- Never place an ad over active combat.
- Prefer opt-in rewarded ads for clearly explained, non-essential rewards.
- Keep interstitials limited to natural breaks such as the result screen.
- Do not sell damage, health, speed, or matchmaking advantages.
- Collect consent before personalised advertising where required.

See [`docs/product/ADS_AND_REWARDS.md`](docs/product/ADS_AND_REWARDS.md) for the planned policy.

## Important legal note

The documents in `docs/legal/` are product drafts and implementation checklists, not legal advice. Before publishing, replace every placeholder, confirm the actual SDKs and data flows, provide a real support/contact address, and have the final text reviewed for the countries where the game is distributed.

## Next implementation milestone

Build a landscape vertical slice containing one fighter, one bot, one arena, health/timer HUD, four touch actions, a result screen, and a clean restart flow. Do not add online matchmaking or ads until the offline combat loop is enjoyable and stable.
