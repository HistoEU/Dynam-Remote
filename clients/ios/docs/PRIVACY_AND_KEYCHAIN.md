# iOS Privacy and Keychain Plan

## MVP Storage

The scaffold stores the last host URL in Keychain so the app can reopen the user-owned host without exposing it in plain app preferences.

The MVP shell does not extract or reimplement the web controller's session token. The current web controller keeps its own browser storage inside `WKWebView` until a native session contract is designed.

## Future Keychain Items

Future native milestones may store:

- last approved host URL;
- redacted host display name;
- session token if the host exposes a native-safe handoff contract;
- trusted-device token only after explicit opt-in;
- account token only for a future paid remote edition.

Each token must have an expiration model and a revoke path. Host revoke must clear or invalidate matching iOS Keychain state on the next sync or connection attempt. Trusted-device storage must remain opt-in and must not silently bypass public-network risk review.

## Expiration and Revoke Behavior

Native iOS session storage should treat these conditions as requiring re-pairing:

- host reports session not found;
- host reports session not approved;
- host reports trusted-device revoked;
- token is expired by host policy;
- host URL changes to a different origin;
- user taps Forget Saved Host.

The app should clear affected Keychain items, close the controller surface, and return to PIN pairing.

## Support Bundle Exclusions

Support bundles and diagnostics must never include:

- raw screen frames;
- raw typed text;
- raw pasted text;
- raw host keys;
- full trusted-device secrets;
- full session tokens;
- private screenshots unless the user explicitly attaches them outside the default bundle.

Allowed diagnostic fields should be redacted or aggregate values such as app version, iOS version, host URL scheme, connection path classification, direct vs relay status, capture stats, error codes, and redacted session IDs.
