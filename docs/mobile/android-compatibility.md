# Android Compatibility Notes

Branch: `mobile/android-shell`

Worker: Worker 4

## Approach Decision

Chosen approach: native Kotlin Android shell with WebView for the current controller.

| Option | Fit | Decision |
|---|---|---|
| Native Kotlin WebView shell | Fastest path to current local Wi-Fi compatibility, good access to Android Keystore later, native haptics/keyboard/orientation hooks, and a clean migration path to native WebRTC. Build complexity is normal Android-only tooling. | Chosen for this branch. |
| Fully native Kotlin controller | Best long-term control over media/input, but it would need to reimplement pairing, command sequencing, RTC, canvas/video behavior, and controller UX now. | Defer until native media contract exists. |
| React Native | Useful for shared app UI, but adds Metro/JS bridge complexity without improving compatibility with the existing browser controller. | Not chosen. |
| Flutter | Good cross-platform UI, but it adds engine size and plugin complexity for WebView, secure storage, WebRTC, and platform input. | Not chosen. |

The branch is a serious app shell, not a native performance claim. Current control semantics remain inside the existing browser controller loaded by WebView.

## Host URL and Session Flow

1. The user enters a host URL, usually `http://<lan-or-tailscale-host>:4317`.
2. The shell stores recent host URLs in Android `SharedPreferences`; host URLs are not treated as secrets.
3. The shell loads the existing controller page in WebView.
4. The WebView controller uses the existing host endpoints:
   - `GET /` for the controller UI.
   - `POST /api/pair` with PIN, device name, and keep-signed-in choice.
   - `GET /api/session?token=...` while waiting for approval or reconnecting.
   - `GET /ws?token=...` for control/state/stream frames.
   - `GET /rtc?role=phone&token=...` for current RTC signaling.
5. Host approval, pending sessions, approved sessions, session expiry, revocation, trusted-device opt-in, and free local Wi-Fi mode stay unchanged.

The Android shell does not add a paid account requirement. Local Wi-Fi pairing remains available without login.

## Control Compatibility

The shell must not send custom native control commands in this milestone. Any future native controller must use:

- `protocolVersion: 1`
- known client message types from `docs/interfaces/control-protocol.md`
- monotonically increasing positive integer `sequence`
- current numeric `timestamp`
- object `payload`

The current native Stop button does not create a new protocol command. It asks the loaded browser controller to click its existing Stop/Disconnect control. If that control is unavailable, the user must use the visible controller Stop control after pairing.

## Secure Storage Plan

Current branch:

- Stores recent host URLs in `SharedPreferences`.
- Leaves current browser session token handling inside WebView storage to preserve compatibility with `public/app.js`.

Next Android security step after an explicit host/browser token handoff contract:

- Use Android Keystore-backed storage, for example AndroidX Security `EncryptedSharedPreferences`, for session tokens and trusted-device token metadata.
- Store:
  - host URL
  - session token
  - trusted-device token or trusted-device metadata if the host exposes a native-safe contract
- Do not store:
  - raw host key
  - raw typed text
  - screen frames
  - exported host logs
  - capture proof artifacts

Trusted-device behavior must remain opt-in and revocable from the host.

## Native Affordances

- Orientation: `fullUser` with `configChanges` keeps the WebView session alive across portrait and landscape rotation.
- Safe areas/insets: the root view applies system window inset padding so the controller is not hidden by status or navigation bars.
- Keyboard: the Activity uses `SOFT_INPUT_ADJUST_RESIZE`; WebView form fields and the existing controller keyboard remain responsible for text entry.
- Haptics: native shell buttons use Android haptic feedback. Existing browser haptics remain controlled by the browser controller.
- Back button: hides the host chooser when open, navigates WebView history when possible, then returns to the host chooser.
- Stop control: the WebView remains the authority for Stop/Disconnect. The native bar offers a shortcut to the loaded controller's existing button but does not fork command semantics.
- Permissions: WebView camera/microphone permission requests are denied in this shell. QR scanning should be a native permissioned feature in a later branch.

## QR Scan Path

The host console already exposes QR-coded controller URLs. A later Android branch should add a native scanner that:

1. Requests camera permission only when the user taps Scan.
2. Accepts only `http` or `https` URLs.
3. Writes the scanned URL into the same host URL field used by manual entry.
4. Does not read or store PINs, typed text, screen frames, or host keys.

## Future Native WebRTC Path

A native Android media client should connect to the same session and RTC trust model before replacing WebView video. It needs:

- Approved session token from the host.
- RTC endpoint and role: `/rtc?role=phone&token=...`.
- RTC protocol `remote-controller-rtc`, version `1`.
- `rtc.ready`, `rtc.offer`, `rtc.answer`, `rtc.ice`, `rtc.stop`, `rtc.status`, and `rtc.ping` lifecycle compatibility.
- Capture metadata fields from `docs/interfaces/capture-and-video-signaling.md`, including width, height, frame rate, display surface, requested monitor/source, audio track/source state, microphone state, and update time.
- Monitor metadata needed by `docs/interfaces/input-safety-and-coordinate-mapping.md`: monitor ID, bounds, scale factor, and selected monitor/source.
- Evidence before any performance claim: FPS, frame timing, input RTT, CPU/GPU impact, and device/Android version.

Until that evidence exists, the current browser/WebRTC capture path remains the compatibility fallback.

## Current Blockers

This machine has Java 21 but no Gradle, Android SDK, `adb`, `sdkmanager`, emulator, `ANDROID_HOME`, or `ANDROID_SDK_ROOT`. Android build, lint, emulator screenshots, and physical-device proof are therefore blocked in this branch environment.

## Validation Performed

From the Worker 4 worktree:

```powershell
npm.cmd ci
node --test test\protocol.test.js test\session-store.test.js test\input-adapter.test.js
```

Result: 19 tests passed.

These checks prove the shared protocol/session/input contracts still pass. They do not prove Android build output or physical phone behavior.
