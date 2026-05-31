# Session Trust and Pairing Contract

Source of truth:

- `src/session-store.js`
- `test/session-store.test.js`
- `src/server.js`
- `public/host.js`
- `public/app.js`

## Pairing Model

The host generates a six-digit PIN with a short expiry. A phone must present the current PIN to create a pending session.

Protected behavior:

- wrong PIN attempts are rate-limited by remote address
- lockout has a visible retry window
- expired PINs refresh
- a successful pairing refreshes the PIN
- pairing logs should not expose private secrets

## Session Approval

A new phone session is pending until the host approves it, unless trusted-device auto-approval is enabled and the device is already trusted.

Protected behavior:

- unapproved sessions cannot control input
- approved sessions have explicit permissions
- sessions expire
- sessions can be revoked
- host console can see active/pending session state

## Trusted Devices

Trusted devices are keyed from device name, user agent, and remote address, then hashed for display-safe IDs.

Protected behavior:

- raw trust keys must not be exposed to the UI
- trusted device records can be listed, revoked, and cleared
- revoking a trusted device also revokes related sessions
- keeping a device signed in must be opt-in, not silent
- trusted devices must not bypass the security model on public/unknown networks without a paid-remote design review

## Free Local vs Paid Remote

Free local Wi-Fi mode must not require account login.

Paid remote work may add account-backed device registry and remote signaling, but it must not remove local PIN pairing or host-side approval as a safe fallback.

## Protected Tests

Run after pairing/session/trust changes:

```powershell
node --test test\session-store.test.js test\protocol.test.js
```

If host console behavior changes, also run host console tests and attach screenshots.

