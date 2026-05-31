# Android Build Notes

Date: 2026-05-31

## Environment Observed

Available:

- `java -version`: Temurin OpenJDK 21.0.6.

Missing on this machine:

- `gradle`
- `adb`
- `sdkmanager`
- `emulator`
- `ANDROID_HOME`
- `ANDROID_SDK_ROOT`

## Build Result

Android build, lint, unit test, emulator, and screenshot validation are blocked by missing Android SDK/Gradle tooling. The source-controlled scaffold is present under `clients/android/` and is intended to open in Android Studio or build after installing SDK Platform 35 and Gradle.

## Commands Run From Repo Root

```powershell
npm.cmd ci
node --test test\protocol.test.js test\session-store.test.js test\input-adapter.test.js
```

Result: 19 tests passed.

Additional broad check:

```powershell
node --test test\*.test.js
```

Result: 87 passed, 3 failed. The failures are in `test\host-console.test.js` because the tests expect phone URLs containing `v=76` while the current generated host-console URLs contain `v=77`. Worker 4 did not change host runtime, `public\host.js`, or `public\app.js`.

## Android Commands Checked

```powershell
java -version
gradle -v
Get-Command adb
Get-Command sdkmanager
Get-Command emulator
$env:ANDROID_HOME; $env:ANDROID_SDK_ROOT
```

Result: Java is installed; Gradle, Android SDK tools, emulator, and Android SDK environment variables are unavailable.
