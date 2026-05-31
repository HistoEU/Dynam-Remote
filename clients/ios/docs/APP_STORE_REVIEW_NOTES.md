# iOS App Store Review Notes

These notes are a review-risk checklist, not a claim that the app is ready for submission.

## Positioning

Dynam Remote should be presented as a remote desktop controller for a user-owned host computer. The user starts the host locally, sees the host console, approves the phone, and can stop or revoke control.

Avoid positioning that resembles:

- hidden surveillance;
- covert monitoring;
- hosted app streaming;
- a marketplace or store inside the app;
- remote control of computers the user does not own or administer.

## Required Reviewer Explanation

The App Review notes should explain:

- the app controls only a user-owned host;
- the host must display a PIN and approve the phone before control;
- Stop/disconnect and host-side revoke controls are available;
- local Wi-Fi mode does not require an account;
- Tailscale is a user-managed private-network option;
- paid remote access is future work and must not be implied unless implemented and reviewed.

## Demo Strategy

If review cannot access a private host:

1. Provide a demo host build or video showing local host launch, PIN pairing, host approval, Stop, and revoke.
2. Provide test credentials only if a future paid account system exists.
3. Provide clear support instructions for reproducing the user-owned-host flow.

## Privacy Disclosures To Prepare

Likely disclosure categories before submission:

- device identifiers or redacted session IDs;
- diagnostics such as OS/app version, connection path, capture stats, and error codes;
- relay metadata if paid remote relay exists later;
- account information only if paid remote login exists later.

Support and diagnostics must not include raw screen frames, raw typed text, raw host keys, full trust tokens, or full trusted-device secrets.

## Review Risks

| Area | Risk | Mitigation |
| --- | --- | --- |
| Local-network HTTP in `WKWebView` | App Transport Security review questions. | Document user-owned local host, restrict use to user-entered host URLs, and keep local-network usage description explicit. |
| Remote desktop control | Misclassification as surveillance. | Emphasize visible host approval, Stop, revoke, and user-owned host framing. |
| Embedded web controller | Review may ask what content is loaded. | Load only user-entered host controller URLs; no third-party hosted app catalog. |
| Future paid remote | Account, relay, and deletion obligations. | Do not ship paid claims until auth, deletion, privacy, support, and relay contracts exist. |
