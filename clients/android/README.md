# Dynam Remote Android Shell

This is the Worker 4 Android app shell direction for Dynam Remote.

Chosen approach: native Kotlin Android app with a WebView controller shell. The shell loads the existing local Wi-Fi controller from a user-entered host URL, so pairing, approval, trusted-device behavior, control messages, Stop behavior, and RTC signaling stay owned by the current host/browser contract.

## Scope

- Manual host URL entry for `http://<host>:4317` or future `https://` hosts.
- Recent host URL storage in Android `SharedPreferences`.
- WebView wrapper for the existing controller flow.
- Native top bar with host switching and a Stop action that clicks the existing browser controller Stop/Disconnect control instead of sending a new protocol command.
- Portrait/landscape handling without recreating the Activity.
- Keyboard resize behavior, safe-area/inset padding, haptic feedback on native shell controls, and browser permission denial for camera/microphone capture prompts.

## Build Prerequisites

Install:

- JDK 17 or newer.
- Android Studio or Android SDK command-line tools.
- Android SDK Platform 35.
- Android build tools compatible with Android Gradle Plugin 8.7.3.
- Gradle or a generated Gradle wrapper.

This branch does not commit a generated Gradle wrapper because this machine does not have Gradle or Android SDK tooling available to generate and verify it.

## Build Commands

From `clients/android` after Android tooling is installed:

```powershell
gradle wrapper --gradle-version 8.10.2
.\gradlew.bat :app:assembleDebug
.\gradlew.bat :app:lintDebug
```

If Android Studio is used first, open `clients/android`, let the project sync, then run the `app` debug configuration.

## Manual Smoke Path

1. Start the Windows host from the repository root:

```powershell
$env:HOST_KEY='dev-host-key'
npm start
```

2. Open the Android app.
3. Enter the same phone URL shown by the host console, for example `http://192.168.1.10:4317`.
4. Pair with the current PIN.
5. Approve the pending session on the host.
6. Confirm the existing browser controller loads, receives video/fallback frames, sends dry-run controls, and keeps Stop controls visible.

## Current Limitations

- No native WebRTC receiver is implemented in this branch.
- No QR scanner is implemented yet; the host console already exposes QR URLs and a later Android scanner should populate the same host URL field.
- Current session tokens remain inside WebView browser storage because the host/browser does not yet expose a native token handoff contract.
- Cleartext HTTP is allowed for local Wi-Fi and Tailscale compatibility. Paid remote access should require HTTPS/WSS.
