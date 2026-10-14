# Product and Engineering Decisions

## ADR-001: Landscape-only orientation

**Decision:** Use landscape for every screen, including menus, tutorials, and results.

**Reason:** The game is a horizontal fighter. A single orientation avoids disruptive rotation during the core flow and leaves room for the arena, HUD, movement control, and action buttons.

## ADR-002: Bot before online 1v1

**Decision:** Build and polish Player vs Bot before online matchmaking.

**Reason:** Combat feel, hit feedback, controls, and rules must be proven locally. Online work should not hide a weak core loop.

## ADR-003: Separate-device online mode only

**Decision:** Do not build two-player same-device controls.

**Reason:** The product target is online 1v1 on separate devices. Removing local split controls keeps the UI focused and reduces scope.

## ADR-004: Server-authoritative online results

**Decision:** The server owns online match time, legal state, damage, and final result.

**Reason:** A client-only result is easy to manipulate and creates unfair matches. Local prediction may improve feel, but it cannot override the authoritative state.

## ADR-005: Non-intrusive monetisation

**Decision:** No ads during combat; prefer optional rewarded ads and limited interstitials at natural breaks.

**Reason:** Premium presentation and player trust are more valuable than short-term ad impressions. Competitive power must not be sold.
