# Issue 7: iOS App Shell Prototype

Labels: `workstream:ios`, `needs-physical-device`

Milestone: `M2 - Mobile App Shells`

Branch: `mobile/ios-shell`

Plan pages: Page 10, Page 20.

## Purpose

Start the iOS app direction while keeping App Store rules in mind. The first iOS workstream should define the shell, host pairing compatibility, Keychain storage, haptics, orientation, keyboard handling, review notes, and future native media path.

## Scope

- Scaffold iOS project or document macOS/Xcode blocker.
- Preserve current local Wi-Fi pairing/session expectations.
- Plan Keychain token storage.
- Add App Store review notes for user-owned host remote desktop.
- Separate MVP shell from later native WebRTC/media implementation.

## Owned Files

- New iOS project folder only.
- iOS setup docs.
- iOS review notes.

## Forbidden Changes

- Do not edit host runtime.
- Do not edit Android project.
- Do not make store/legal claims without review notes.
- Do not claim App Store readiness without a demo/review strategy.

## Required Interface Contracts

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/session-trust-and-pairing.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Starter Brief

- `docs/workstreams/ios-app-shell.md`

## Acceptance Evidence

- iOS scaffold/build note or environment blocker.
- App Store compliance checklist exists.
- Compatibility note explains current host expectations.
