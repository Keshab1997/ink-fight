# QA and Release Checklist

## Product and UX

- [ ] App opens to a working landscape splash screen.
- [ ] Main menu primary action is clear.
- [ ] All buttons have pressed, disabled, and loading states.
- [ ] Safe areas are respected on cutout and rounded-corner devices.
- [ ] Character select communicates locked and available content honestly.
- [ ] Tutorial can be skipped and replayed.
- [ ] Fight HUD remains readable during effects.
- [ ] Pause, resume, rematch, and return-to-menu paths are safe.
- [ ] Win, loss, draw, cancellation, and reconnect states are distinct.

## Combat

- [ ] Movement, jump, attack, heavy attack, and block respond reliably.
- [ ] Hitboxes/hurtboxes have been tested in debug mode.
- [ ] Bot does not use impossible timing, damage, or hidden health.
- [ ] Timer, health, cooldown, and result rules match the ruleset version.
- [ ] Match resets all temporary state.
- [ ] Backgrounding and returning to the app do not create a free hit.

## Online

- [ ] Queue cancellation works.
- [ ] Both players receive the same match start and result.
- [ ] Duplicate and out-of-order inputs are handled.
- [ ] Simulated latency and packet loss have been tested.
- [ ] Reconnect grace period and timeout are documented.
- [ ] Server rejects impossible actions and client result claims.
- [ ] Rematch cannot carry over health or temporary effects.
- [ ] Report/block flow does not expose private information.

## Ads and privacy

- [ ] Development builds use test ad units.
- [ ] No ad appears during active combat or reconnect.
- [ ] Reward is explained before opt-in.
- [ ] Failed ad does not deduct currency or block the player.
- [ ] Consent flow matches actual SDK behaviour and target regions.
- [ ] Privacy policy and data safety answers match the shipped data flow.
- [ ] Production secrets are not in source control.
- [ ] Data deletion/support route works and is documented.

## Performance and devices

- [ ] Low-end Android test completed.
- [ ] Current Android test completed.
- [ ] 16:9, 18:9, and 20:9 layouts checked.
- [ ] No major frame-time spike during hit effects.
- [ ] Memory use remains stable over repeated rematches.
- [ ] App survives offline start, network loss, and background/foreground cycles.

## Store and support

- [ ] App name, package ID, icon, screenshots, and description are consistent.
- [ ] Age/content rating questionnaire is complete.
- [ ] Support contact is real and monitored.
- [ ] Terms, Privacy Policy, Community Guidelines, and deletion instructions are published.
- [ ] Release notes mention known limitations honestly.
- [ ] Rollback/staged rollout plan is ready.
