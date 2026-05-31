# iOS Build Notes

## Current Environment Blocker

This work was prepared on Windows. Xcode, `xcodebuild`, iOS Simulator, and iOS code signing are macOS-only, so the scaffold was not built or launched in this workspace.

Evidence that can be gathered here:

```powershell
node --test clients\ios\tests\ios-scaffold.test.js
node --test test\protocol.test.js test\session-store.test.js test\input-adapter.test.js
```

Evidence that still requires macOS/Xcode:

```bash
cd clients/ios
xcodebuild -project DynamRemote.xcodeproj -scheme DynamRemote -destination 'platform=iOS Simulator,name=iPhone 15' build
xcrun simctl boot 'iPhone 15'
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/DynamRemote.app
xcrun simctl launch booted com.dynamremote.iosshell
```

Use Xcode's standard screenshot tool or `xcrun simctl io booted screenshot ios-shell.png` after launch.

## Expected Xcode Setup

1. Open `clients/ios/DynamRemote.xcodeproj`.
2. Select the `DynamRemote` scheme.
3. Set the signing team under target settings if running on a physical iPhone.
4. Use iOS 16 or later.
5. Start the Dynam Remote host on the same Wi-Fi or over Tailscale.
6. Paste the host phone URL into the iOS shell.
7. Pair with the current PIN and approve on the host.

## Build Claims

Do not claim App Store, physical iPhone, native media, or simulator readiness until the macOS/Xcode commands above have produced evidence.
