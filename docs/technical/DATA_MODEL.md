# Data Model Draft

This is a product-level model, not a final database schema. Field names and retention must match the selected backend and final privacy notice.

## PlayerProfile

- `playerId` — server-generated stable identifier.
- `displayName` — optional public name with moderation constraints.
- `avatarOrCosmeticIds` — cosmetic references only; no combat stats.
- `createdAt`, `updatedAt`.
- `lastSeenAt` — coarse operational timestamp if needed.
- `status` — active, restricted, deleted.

## Match

- `matchId` — opaque identifier.
- `mode` — bot, online casual, future ranked.
- `roomId` — temporary room reference, if online.
- `playerIds` — server-controlled references.
- `rulesetVersion` — ensures result interpretation remains stable.
- `startedAt`, `endedAt`.
- `result` — win, loss, draw, cancelled, unresolved.
- `disconnectReason` — optional controlled value.
- `createdVersion` — app/server compatibility.

Do not store raw input streams by default. If short diagnostic samples are ever retained, disclose purpose and retention.

## ConsentRecord

- `playerId` or consent scope identifier.
- `consentVersion`.
- `choices` — e.g. personalised ads, analytics, required services.
- `capturedAt`.
- `withdrawnAt` if applicable.

## CosmeticEntitlement

- `entitlementId`.
- `playerId`.
- `cosmeticId`.
- `source` — earned, purchase, rewarded ad, grant.
- `createdAt`.
- `idempotencyKey` for duplicate-safe claims.

## Report

- `reportId`.
- `reporterPlayerId`.
- `reportedPlayerId` if known.
- `matchId`.
- `category`.
- `note` — sanitised, length-limited.
- `status`.
- `createdAt`, `reviewedAt`.

## Deletion

Account deletion must mark the account, revoke sessions, remove or anonymise linked data according to the final retention policy, and prevent future reward claims. The implementation must expose a player-facing route or an approved support workflow before launch.
