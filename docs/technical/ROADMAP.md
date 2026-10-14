# Development Roadmap

## Phase 0 — Product foundation

- Finalise this specification and legal placeholders.
- Confirm visual identity, logo, typography, and landscape breakpoints.
- Create the Flutter/Flame shell and a deterministic combat rules package.
- Set up a safe asset pipeline and a debug hitbox mode.

**Exit gate:** screens, controls, naming, package ID, and data boundaries are agreed.

## Phase 1 — Premium offline vertical slice

- Splash, main menu, settings, character select, arena, pause, result.
- One doodle fighter, one bot fighter, one arena.
- Movement, jump, light attack, heavy attack, block, hit feedback.
- Bot difficulty presets and rematch.
- Landscape safe-area layout and device testing.

**Exit gate:** a new player can complete a stable match without crashes or confusing states.

## Phase 2 — Content and polish

- Additional cosmetic variations.
- Better animation, ink effects, audio, haptics, transitions.
- Tutorial, accessibility options, local settings, performance pass.
- Analytics plan and crash diagnostics with approved consent behaviour.

**Exit gate:** closed playtest feedback is addressed and the game feels coherent without monetisation.

## Phase 3 — Online casual 1v1

- Authentication/session strategy.
- Queue, room, ready check, authoritative match, result, rematch.
- Reconnect and safe failure rules.
- Report/block flow and basic moderation tooling.
- Network simulation and device/region test pass.

**Exit gate:** test players can complete repeatable matches with clear outcomes under normal latency and controlled packet loss.

## Phase 4 — Monetisation and store readiness

- AdMob test integration, consent, reward idempotency, and natural placements.
- Privacy policy, Terms, data safety answers, support route, and data deletion.
- Store screenshots, icon, description, rating questionnaire, and release notes.
- Production keys/secrets supplied only through secure release configuration.

**Exit gate:** legal, privacy, monetisation, support, and release checklist are complete.

## Phase 5 — Launch and iteration

- Staged rollout.
- Monitor crashes, match completion, latency, retention, and ad failures.
- Fix quality issues before adding ranked play.
- Review community reports and update rules transparently.

## Explicitly later

Ranked seasons, extra fighters, extra arenas, clans, live chat, tournaments, and deeper cosmetics are all later decisions. They should not delay a strong first combat loop.
