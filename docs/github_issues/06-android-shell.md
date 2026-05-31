# Issue 6: Android App Shell Prototype

Labels: `workstream:android`, `needs-physical-device`

Milestone: `M2 - Mobile App Shells`

Branch: `mobile/android-shell`

Plan pages: Page 9, Page 11, Page 19.

## Purpose

Start the Android app direction without destabilizing the existing host or browser controller. The first Android workstream should prove the shell, pairing compatibility, orientation handling, keyboard/haptics direction, and future native media path.

## Scope

- Scaffold Android project or document exact environment blocker.
- Preserve current local Wi-Fi pairing/session expectations.
- Plan secure storage through Android Keystore-backed storage.
- Plan orientation, safe areas, haptics, keyboard, and future native WebRTC.

## Owned Files

- New Android project folder only.
- Android setup docs.
- Android screenshots or build notes.

## Forbidden Changes

- Do not edit host runtime.
- Do not edit iOS project.
- Do not fork command semantics silently.
- Do not promise native video performance before measuring it.

## Required Interface Contracts

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/session-trust-and-pairing.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Starter Brief

- `docs/workstreams/android-app-shell.md`

## Acceptance Evidence

- Android scaffold builds, or environment blocker is written clearly.
- Compatibility note explains how it connects to current host.
- App shell scope is separated from future native WebRTC/media work.
