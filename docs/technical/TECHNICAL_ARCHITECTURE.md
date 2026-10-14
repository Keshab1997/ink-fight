# Technical Architecture

## Status

This is the implementation plan for the first Flutter/Flame vertical slice and the later online mode. It intentionally separates game rules from rendering and networking so the same combat model can be tested locally and validated by a server.

## Stack direction

- **Client:** Flutter for application UI and navigation; Flame for the real-time 2D arena.
- **Language:** Dart on the client.
- **Rendering:** doodle sprites/vector-like assets, particle effects, and a controlled monochrome palette.
- **Persistence:** local settings and progression store; the exact package is selected during implementation.
- **Authentication:** guest-first or platform sign-in for the first online prototype; final provider is a release decision.
- **Realtime transport:** server-authoritative WebSocket or an equivalent realtime game service.
- **Monetisation:** Google Mobile Ads / AdMob with the consent flow required for the target distribution.
- **Observability:** crash/ANR reporting and minimal gameplay telemetry, only after the privacy/data map is approved.

The backend provider is intentionally not hard-coded in this document. It must be selected after latency, hosting, pricing, and Flutter support are tested with a small prototype.

## Client layers

```text
Flutter App Shell
 ├─ Navigation and screen state
 ├─ Settings, consent, support, and account UI
 └─ Ad and platform integrations

Game Feature Layer
 ├─ Match state machine
 ├─ Fighter input and combat rules
 ├─ Bot strategy
 ├─ HUD and touch controls
 └─ Result and rematch flow

Flame Presentation Layer
 ├─ Arena world
 ├─ Fighter components
 ├─ Hit effects and camera response
 └─ Asset loading and animation

Infrastructure
 ├─ Local persistence
 ├─ Auth/session
 ├─ Realtime transport
 ├─ Analytics/diagnostics
 └─ Feature flags
```

## Domain boundaries

- `MatchRules` contains deterministic rules such as health, timers, legal actions, cooldowns, and hit resolution.
- `FighterState` contains serialisable state; it must not depend on a widget or rendering object.
- `InputCommand` contains intent, sequence number, client timestamp, and action payload. It must never contain a claimed result.
- `MatchSnapshot` is a server-authoritative state or a local simulation state in bot mode.
- `MatchController` coordinates a local bot match or online transport without putting network code inside fighter rendering components.
- `ResultState` is entered only after the match controller confirms the outcome.

## Orientation and performance

- Lock the app to landscape left/right.
- Use safe-area insets for HUD and touch controls.
- Target 60 FPS on supported devices; test frame time on low-end Android hardware.
- Load only the first arena and selected fighter before a match; defer non-critical assets.
- Avoid allocations inside the per-frame update loop where possible.
- Keep visual effects bounded so hit feedback never hides a fighter or input button.

## Online model

A client can predict local movement for responsiveness, but the server owns the match clock, legal state transitions, collision result, damage, and final result. Inputs use sequence numbers so the client can reconcile predicted state with an authoritative snapshot.

Minimum server responsibilities:

- Authenticate the session and create a match room.
- Validate input cadence and state transitions.
- Advance the authoritative simulation.
- Broadcast snapshots or deltas at a tested rate.
- Store the final result and idempotent reward claim.
- Close rooms safely after timeout or both players leave.

## Security rules

- Never commit tokens, signing keys, AdMob production IDs that are intended to be secret, keystores, `google-services.json`, or private backend credentials.
- Treat every client value as untrusted.
- Do not log auth tokens, payment details, private messages, or raw device identifiers unnecessarily.
- Keep debug hitboxes, debug commands, and test reward endpoints out of release builds.
- Use server-side validation for all online entitlements.

## Testing strategy

- Unit tests for combat rules, cooldowns, hit resolution, and result states.
- Golden/widget tests for key landscape UI states where practical.
- Flame integration tests for input-to-action and match reset.
- Bot tests for legal action generation and difficulty boundaries.
- Network simulation tests for latency, dropped packets, reconnect, duplicate events, and server rejection.
- Manual device matrix covering low-end Android, current Android, cutouts, and different aspect ratios.
