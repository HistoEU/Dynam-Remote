# TOTP Trusted Device Design

This is the security design for adding authenticator-app codes without weakening first-time laptop approval.

## Decision

TOTP is an optional trusted-device upgrade. It must not replace the first pairing PIN and laptop approval flow. The first connection still requires:

1. The phone opens the local Wi-Fi or Tailscale URL.
2. The phone enters the short-lived pairing PIN.
3. The laptop host approves that pending session.
4. Only after approval may the user enroll an authenticator code for future repeat connections.

## Enrollment Flow

1. The host generates a random TOTP secret for the approved device.
2. The host displays a QR code in the host console only.
3. The user scans the QR code with an authenticator app.
4. The phone must prove enrollment by submitting one current six-digit TOTP code while the approved session is still active.
5. The host stores only the encrypted/hashed trusted-device record and the TOTP secret material needed to verify future codes.
6. The host records the enrollment event in logs without exposing the raw secret.

## Repeat Connection Flow

1. The phone presents its remembered trusted-device key.
2. The host verifies that the device is still trusted and not revoked.
3. The phone enters the current TOTP code from the authenticator app.
4. The host verifies the code with a small clock-skew window.
5. If valid, the session can skip manual laptop approval.
6. If invalid, the existing rate limit and lockout rules apply.

## Safety Rules

- TOTP never opens public access by itself.
- TOTP must work only over already allowed network paths: loopback, private LAN, or Tailscale/private VPN.
- Revoking a trusted device immediately disables its remembered key and TOTP enrollment.
- Stop and kill-switch behavior must still release all held mouse buttons and keys.
- Failed TOTP attempts must not reveal whether the trusted-device key or the code was the wrong part.
- Raw TOTP secrets must not appear in exported logs, phone diagnostics, screenshots, or package smoke output.

## UI Placement

The phone controller should stay clean. TOTP enrollment belongs in the host console trusted-device area after a device has been approved. The phone should only show a compact code prompt when a remembered trusted device requires a current authenticator code.

## Implementation Notes

- Use a standard TOTP algorithm compatible with authenticator apps: HMAC-SHA1, six digits, 30-second period.
- Use `otpauth://totp/...` QR payloads with a stable issuer name such as `Remote Controller`.
- Store an enrollment version and monitor revocation state so future schema changes can invalidate old records safely.
- Add tests for successful enrollment, rejected wrong code, rate limiting, revocation, log redaction, and repeat connection with trusted-device plus TOTP.

## Acceptance

The feature is ready only when first-time approval is still mandatory, repeat connection requires both the trusted key and current authenticator code, revocation works immediately, and logs never expose raw secrets.
