# Account and Data Deletion Plan

## Player-facing promise

Players must have a clear way to ask for deletion of their INK FIGHT account and associated personal data. The exact UI and retention wording must match the final backend and Privacy Policy.

## Preferred in-app flow

1. Open **Settings**.
2. Open **Account and Privacy**.
3. Choose **Delete Account and Data**.
4. Read the consequences, including loss of progress and cosmetics that cannot legally be restored.
5. Confirm using the account/session verification step.
6. Show a request ID and expected completion window.
7. Sign the player out and block new sessions while deletion is pending.

## Support fallback

If in-app deletion is temporarily unavailable, publish a monitored address such as `[PRIVACY_EMAIL]`. Never ask a player to send a password, one-time code, payment card number, or private key. Verify the requester using a safe account process.

## Deletion checklist

- [ ] Revoke active sessions and reconnect tokens.
- [ ] Mark the account as pending deletion immediately.
- [ ] Remove or anonymise profile and display-name data according to the retention policy.
- [ ] Remove or anonymise linked cosmetic entitlements where required.
- [ ] Remove or anonymise support/report links where legally allowed and safe.
- [ ] Keep only narrowly defined records needed for fraud, security, chargebacks, or legal obligations.
- [ ] Remove analytics identifiers and advertising consent links according to provider controls.
- [ ] Include backups and define the backup expiry window.
- [ ] Prevent reward duplication after deletion.
- [ ] Notify the player when the request is complete or explain a lawful exception.

## Product requirements

The final app must explain what deletion removes, what may be retained temporarily, whether the action is reversible, and how a player can contact support. The Play Store data-safety answers and public privacy policy must describe the same process.
