# Backend and Matchmaking Plan

## Goal

Provide short, fair online 1v1 matches on separate devices without trusting either client. The service must be able to reject impossible input, handle temporary disconnects, and return one authoritative result.

## Logical services

1. **Identity/session** — guest or platform account, short-lived access token, refresh/revoke path.
2. **Matchmaking** — queue, region/latency preference, skill band later, cancellation.
3. **Room service** — two-player room, ready state, countdown, disconnect grace period.
4. **Authoritative simulation** — match clock, movement legality, combat, damage, win condition.
5. **Result/entitlement** — idempotent result write, cosmetic rewards, rematch request.
6. **Moderation/reporting** — report category, match reference, review state, limited metadata.

## Match state machine

```text
IDLE
  → QUEUED
  → MATCH_FOUND
  → CONNECTING
  → READY_CHECK
  → COUNTDOWN
  → IN_PROGRESS
  → RESULT_PENDING
  → COMPLETE

Any state may go to CANCELLED or DISCONNECTED when the server applies the relevant rule.
```

## Example event contract

These names are illustrative and must be versioned before production.

### Client to server

- `queue.join { mode, clientVersion, regionHint }`
- `queue.cancel { requestId }`
- `room.ready { roomId }`
- `match.input { roomId, sequence, action, clientTick }`
- `room.rematch { roomId }`
- `room.leave { roomId }`
- `report.submit { matchId, category, note }`

### Server to client

- `queue.status { requestId, state, estimatedWait }`
- `room.found { roomId, opponentSummary, expiresAt }`
- `room.state { readyCount, connectionState }`
- `match.countdown { endsAt }`
- `match.snapshot { tick, state, ackSequence }`
- `match.event { type, entityId, eventId }`
- `match.result { matchId, outcome, reason, resultId }`
- `room.rematchState { requestedBy, expiresAt }`
- `error { code, message, retryable }`

## Validation

The server rejects:

- Unknown or expired room IDs.
- Inputs from a player who is not in the room.
- Impossible action order, action cadence, movement, or cooldown state.
- Duplicate sequence numbers without idempotent handling.
- Events from a client version that is no longer supported.
- Result/reward claims that do not reference a completed server result.

## Latency and reconnect

- Measure round-trip time during the ready check and expose a simple quality indicator.
- Use sequence acknowledgements and a bounded input buffer.
- Reconnect tokens must be short-lived and scoped to the room; never put them in logs.
- Freeze or safely simulate the disconnected fighter according to the final rules, then resume or apply the documented timeout.
- Do not award ranked points for an unresolved server failure.

## Anti-abuse limits

- Rate-limit queue requests, reports, and reconnect attempts.
- Cap report volume per account/device to reduce spam while preserving an appeal route.
- Keep moderation data separate from public profile data.
- Record version and match IDs for investigation, but minimise personal data.

## Operational readiness

Before online launch, define:

- Service region and hosting plan.
- Maximum concurrent rooms for the first rollout.
- Monitoring for connection errors, match completion, and server tick health.
- Backup and retention policy.
- Maintenance message and safe shutdown flow.
- Incident response owner and player-facing status message.
