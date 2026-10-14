# Online 1v1 Rules

## Scope

Online 1v1 is a later mode for two players on separate devices. It is not local same-device multiplayer. The first online release should be casual and focused on stable, fair matches before ranked competition is added.

## Match lifecycle

```text
Queue → Match found → Connection check → Both ready → Countdown
→ Authoritative match → Result confirmed → Rematch or exit
```

## Matchmaking

- Match players using a region/latency-aware queue when available.
- Do not start a match when a device fails the minimum connection check.
- Show a clear searching, found, connecting, ready, and cancelled state.
- Do not reveal unnecessary personal information to an opponent.
- Ranked matchmaking is out of scope until disconnect and abuse handling are reliable.

## Authority and fairness

- The server owns the match clock, legal state transitions, damage result, and final outcome.
- Clients send input intent with sequence numbers; they do not send “I won” messages.
- Server validation rejects impossible movement, attack cadence, or state transitions.
- The client may predict local motion for responsiveness, but the server snapshot is authoritative.
- Match results are saved only after the server confirms a completed match.

## Disconnect handling

- A brief reconnect window should be available when the player can return safely.
- The opponent sees a clear reconnect state rather than a frozen character.
- Repeated or deliberate disconnects may count as a loss after the final grace period.
- If the server cannot determine a fair result, do not award or remove ranked points.
- The exact grace period and penalty must be playtested and documented in the live rules.

## Rematch

- Either player may request a rematch from the result screen.
- The request expires after a visible countdown.
- A rematch creates a fresh match state; it must not reuse health, timers, or temporary effects.
- A player can leave without being forced to rematch.

## Reporting

Players can report cheating, harassment, or a technical issue after a match. Reports should include a match identifier and category, not private passwords or payment details. False or abusive reporting can itself be moderated.

## Competitive integrity

Never sell health, damage, speed, hitbox, or matchmaking advantages. Cosmetics, victory poses, paper themes, and profile items may be sold or earned if they do not affect the fight.
