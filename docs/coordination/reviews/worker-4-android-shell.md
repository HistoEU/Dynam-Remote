# Worker 4 Review - Android Shell

## Review Target

- Worker: Worker 4
- Branch: `mobile/android-shell`
- Local path: `C:\tmp\dynam-worker-4-android-shell`
- Base reviewed against: `origin/main`
- Worker commit reviewed: `09c86ab` (`Add Android app shell scaffold`)
- Orchestrator follow-up commit: `47add9d` (`Harden Android WebView host boundary`)
- Review date: 2026-05-31

## Worker Claim

Adds a native Kotlin Android/WebView shell scaffold, manual host URL entry, recent-host storage, native Hosts/Stop toolbar, local cleartext configuration for LAN/Tailscale, build notes, Android compatibility docs, and future native media/security notes.

## Changed Files

Android app:

- `clients/android/.gitignore`
- `clients/android/BUILD_NOTES.md`
- `clients/android/README.md`
- `clients/android/settings.gradle.kts`
- `clients/android/build.gradle.kts`
- `clients/android/gradle.properties`
- `clients/android/app/build.gradle.kts`
- `clients/android/app/src/main/AndroidManifest.xml`
- `clients/android/app/src/main/java/eu/histo/dynamremote/MainActivity.kt`
- `clients/android/app/src/main/res/values/colors.xml`
- `clients/android/app/src/main/res/values/strings.xml`
- `clients/android/app/src/main/res/values/styles.xml`
- `clients/android/app/src/main/res/xml/network_security_config.xml`

Tests:

- `test/android-shell-scaffold.test.js` added by orchestrator.

Docs:

- `docs/mobile/android-compatibility.md`

Generated or suspicious artifacts: none committed.

## Scope Check

- Owned scope followed: yes.
- Forbidden scope touched: no host runtime, iOS project, paid relay, or browser behavior changes.
- Interface note required: no runtime interface change; Android compatibility docs were added.
- Interface note present: yes.
- Shared safety behavior affected: no weakening observed.

## Product Safety Check

- Free local Wi-Fi remains accountless: yes.
- Host approval remains intact: yes, the WebView loads the existing pairing flow.
- Stop control remains intact: yes, native Stop invokes the existing browser disconnect button.
- Revoke controls remain intact: yes, host remains authority.
- Trusted-device boundaries remain intact: yes.
- Real-input safety remains intact: yes.
- No raw screen frames or typed text added to logs/support exports: yes.
- No secrets or local state committed: yes.

## Review Finding Fixed By Orchestrator

- P1 fixed: The initial WebView navigation policy allowed every `http` and `https` navigation to remain inside the app. That could turn the remote-control shell into a general-purpose third-party browser surface. The orchestrator patch scopes WebView navigation to the user-entered host origin and opens external destinations through Android's activity resolver. Fixed in `MainActivity.kt` around lines 41, 221, 247, and 300 with commit `47add9d`.

## Validation Run By Orchestrator

Commands run from `C:\tmp\dynam-worker-4-android-shell`:

```powershell
java -version
Get-Command gradle -ErrorAction SilentlyContinue
Get-Command adb -ErrorAction SilentlyContinue
Get-Command sdkmanager -ErrorAction SilentlyContinue
Get-Command emulator -ErrorAction SilentlyContinue
echo "ANDROID_HOME=$env:ANDROID_HOME"
echo "ANDROID_SDK_ROOT=$env:ANDROID_SDK_ROOT"
node --test test\android-shell-scaffold.test.js test\protocol.test.js test\session-store.test.js test\input-adapter.test.js
```

Results:

- Java available: Temurin OpenJDK 21.0.6.
- Gradle, adb, sdkmanager, emulator, `ANDROID_HOME`, and `ANDROID_SDK_ROOT` unavailable.
- Focused tests passed: 20/20.

Full suite:

```powershell
# Started an isolated host on port 47649 with HOST_KEY=dev-host-key, CAPTURE_MODE=screen, REAL_INPUT=0.
npm test
```

Result:

- Passed with exit code 0.

## Manual / Browser / Device Evidence

- Android Gradle build: not run; Gradle and Android SDK unavailable.
- Android emulator: not run; emulator unavailable.
- Physical Android device: not run.

## Findings

No remaining blocking code findings for an Android scaffold.

Launch gate:

- This branch must not be treated as a launch-ready Android app until Gradle sync/build, emulator smoke, and physical Android same-Wi-Fi pairing/Stop/revoke proof exist.

## Merge Decision

Merge approved as scaffold after orchestrator fix `47add9d`.

## Follow-Up

- Required before merge: none from this review.
- Required before product launch: Gradle wrapper or documented Android Studio import, `:app:assembleDebug`, lint, emulator screenshot, physical Android same-Wi-Fi acceptance, and explicit signing/package path.
- Assigned owner: next Android acceptance worker plus orchestrator.
