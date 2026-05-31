# Android App Shell Brief

Branch: `mobile/android-shell`

Issue:

- `06-android-shell.md`

Plan pages:

- Page 9: Android App Plan
- Page 11: Input, Gesture, and UX Finalization
- Page 19: UI Polish and Product Feel

## Mission

Create the Android app direction without breaking the current browser/host product. The first Android milestone is not a perfect native video client; it is a compatible app shell that can load/connect to the host, prove secure storage/onboarding/orientation/haptics direction, and document the later native WebRTC path.

## Owns

- new Android project folder only
- Android setup docs
- Android app shell screenshots/build notes
- Android compatibility notes

## Does Not Own

- existing host protocol
- package scripts
- iOS app
- browser/PWA rewrite
- paid backend

## Must Read First

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/session-trust-and-pairing.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/capture-and-video-signaling.md`

## MVP Choices to Decide

Document the choice before scaffolding:

- native Kotlin shell
- WebView shell
- React Native
- Flutter

Decision criteria:

- fastest connection to current local Wi-Fi host
- native keyboard quality
- haptics quality
- secure storage support
- future native WebRTC support
- build complexity on the user's computer

## Required Product Behavior

- app can enter or scan host URL
- app can pair with PIN
- app can preserve trusted-device/account token later through secure storage
- app handles portrait and landscape
- app does not fork command semantics from browser controller
- app can expose haptics and native keyboard affordances later

## Native Media Later

The Android shell should not pretend WebView video is the final high-speed solution. Later work should evaluate native WebRTC receive/decode and possibly native gesture rendering if browser/WebView timing is too jittery.

## Validation

Minimum evidence:

- scaffold builds, or environment blocker is documented
- screenshot/emulator note if available
- compatibility note showing expected host URL/session flow
- no host files changed unless an interface note exists

## Done Means

The repo has a clear Android starting point and the next Android worker knows whether to build WebView shell, native Kotlin shell, or deeper native media.

