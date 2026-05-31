# Dynam Remote iOS Shell

Worker 5 owns this folder as the iOS starting point for Dynam Remote. The current host and browser/PWA controller remain the compatibility baseline.

## Chosen Approach

Chosen milestone: **Hybrid SwiftUI + WKWebView**.

The app uses SwiftUI for the native host-entry shell, Keychain-backed host URL storage, safe-area navigation, haptics, and an always-reachable Stop control. The controller surface loads the existing host-served phone app in `WKWebView`, so PIN pairing, pending host approval, trusted-device behavior, Stop/disconnect, and current WebRTC/browser fallback behavior stay compatible with the free local Wi-Fi product.

## Options Compared

| Option | Strength | Risk |
| --- | --- | --- |
| SwiftUI + WKWebView shell | Fastest compatibility with current host and PWA flow. Minimal protocol risk. | Native keyboard, haptics, and media performance remain partly browser-bound until later milestones. |
| SwiftUI native client from the start | Best long-term native input, Keychain, and media control. | Requires duplicating the controller protocol now and creates high regression risk for approval, Stop, revoke, and input safety. |
| Hybrid native shell with web controller surface | Keeps web controller compatibility while moving onboarding, storage, haptics, orientation, and review posture into native iOS. | Requires careful App Store explanation for local-network HTTP and a future migration plan for native WebRTC. |

Recommendation: use the hybrid shell first. It gives the next iOS worker a real Xcode project without destabilizing the local Wi-Fi controller or claiming native media performance before evidence exists.

## Project Layout

- `DynamRemote.xcodeproj/` - source-controlled Xcode project shell.
- `DynamRemote/` - SwiftUI app, host entry, `WKWebView` wrapper, Keychain helper, and plist.
- `docs/BUILD_NOTES.md` - macOS/Xcode build instructions and current Windows blocker.
- `docs/COMPATIBILITY.md` - host URL, pairing, trust, Stop, local Wi-Fi, Tailscale, and future paid-remote compatibility.
- `docs/APP_STORE_REVIEW_NOTES.md` - App Store positioning and review-risk checklist.
- `docs/PRIVACY_AND_KEYCHAIN.md` - Keychain and privacy/support-bundle plan.
- `docs/FUTURE_NATIVE_MEDIA.md` - future native WebRTC requirements and fallback plan.
- `tests/ios-scaffold.test.js` - repo-safe structure and contract checks runnable on Windows.

## Setup

On macOS with Xcode installed:

```bash
cd clients/ios
open DynamRemote.xcodeproj
```

Then select the `DynamRemote` scheme, choose an iPhone simulator or physical iPhone, set a development team if signing is required, and run the app.

Command-line build target:

```bash
xcodebuild -project DynamRemote.xcodeproj -scheme DynamRemote -destination 'platform=iOS Simulator,name=iPhone 15' build
```

This Windows workspace cannot run Xcode or an iOS simulator. See `docs/BUILD_NOTES.md` for the exact blocker and validation that was possible here.

## Runtime Flow

1. The host runs the existing local Wi-Fi/Tailscale server and shows a phone URL.
2. The iOS shell accepts a pasted or typed host URL. QR scanning is intentionally left for a later camera-permission milestone.
3. The shell stores the host URL in Keychain.
4. `WKWebView` loads the existing controller page from the host.
5. The user pairs with the current six-digit PIN and waits for host approval inside the existing controller flow.
6. The native Stop button clicks the existing web disconnect control when available and closes the controller surface.

No account login is required for free local Wi-Fi mode.
