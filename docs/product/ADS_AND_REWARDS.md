# Ads and Rewards Plan

## Principle

AdMob should support the game without making the game feel cheap or interrupting the fight. No advertisement appears over active combat.

## Planned placements

### Rewarded ads

Use only when the player actively opts in after seeing a clear explanation. Possible rewards:

- A small amount of cosmetic currency after a completed match.
- A daily reward multiplier.
- A non-competitive retry or practice reward.

The player must know the reward before accepting. If the ad fails, the player must not be punished and the UI must explain that the reward was not granted.

### Interstitial ads

Use only at a natural transition such as after the result screen and before returning to a menu. Frequency must be conservative and configurable. Never show one during a countdown, active combat, reconnect, or purchase flow.

### Banners

Avoid banners in the fight arena. If a banner is tested, keep it limited to a non-critical menu and verify that it does not cover controls or make the premium layout look cluttered.

## Consent and privacy

- Integrate the platform-appropriate consent flow before personalised advertising.
- Support non-personalised ads where required by consent choices.
- Disclose the ad SDK and relevant identifiers in the final privacy notice and store data-safety form.
- Provide a way to revisit consent in Settings when the platform or policy requires it.
- Use test ad units during development; production IDs and secrets must not be committed to the repository.

## Reward integrity

- Never grant premium or competitive power from an ad.
- Store reward claims server-side when online entitlements exist.
- Make reward requests idempotent so a retry cannot duplicate a reward.
- Log only the minimum event data needed to diagnose failures.
- Do not ask players to click ads, and do not encourage accidental clicks.

## Release gate

Ads cannot be enabled for release until the actual SDK version, consent flow, ad placements, privacy policy, data-safety answers, test-device setup, and failure states have been reviewed together.
