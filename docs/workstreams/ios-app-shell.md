# iOS App Shell Brief

Branch: `mobile/ios-shell`

Issue:

- `07-ios-shell.md`

Plan pages:

- Page 10: iOS App Plan
- Page 20: Store, Legal, and Policy Readiness

## Mission

Create the iOS app direction while staying compatible with the current host and realistic about App Store review. The first iOS workstream should define the shell, pairing compatibility, Keychain storage, haptics, keyboard handling, orientation, review notes, and future native WebRTC path.

## Owns

- new iOS project folder only
- iOS setup docs
- App Store review notes
- iOS compatibility notes

## Does Not Own

- host runtime
- Android project
- paid backend
- browser/PWA runtime behavior
- final legal claims

## Must Read First

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/session-trust-and-pairing.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/capture-and-video-signaling.md`

## MVP Choices to Decide

Document the choice before scaffolding:

- SwiftUI plus WKWebView shell
- SwiftUI with native WebRTC from the beginning
- hybrid shell where pairing/settings are native and controller surface is web

Decision criteria:

- fastest route to App Store-compatible prototype
- native keyboard and haptics quality
- secure Keychain storage
- screen orientation behavior
- future native WebRTC feasibility

## Review Positioning

The app should be positioned as a remote desktop controller for user-owned host computers. It should not look like hosted app streaming, hidden surveillance, or a store-like experience inside another app.

Required review notes later:

- user owns/controls the host machine
- host must approve/trust phone
- privacy disclosures for identifiers, diagnostics, relay metadata, and account info
- demo/support mode if review cannot access a real host

## Validation

Minimum evidence:

- iOS scaffold/build notes, or Xcode/macOS blocker
- compatibility note showing expected host URL/session flow
- review-risk checklist
- no host files changed unless an interface note exists

## Done Means

The repo has a clear iOS starting point and the next iOS worker can proceed without guessing store positioning or host compatibility.

