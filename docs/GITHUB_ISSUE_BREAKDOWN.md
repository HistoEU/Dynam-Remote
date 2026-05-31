# GitHub Issue Breakdown

This file converts the product execution plan into GitHub issue-ready chapters. The 25-page plan remains the authoritative deep manual; this file is the practical issue index that lets multiple Codex instances work without collateral damage.

## Labels to Create

- `workstream:repo`
- `workstream:browser`
- `workstream:android`
- `workstream:ios`
- `workstream:remote`
- `workstream:capture`
- `workstream:display`
- `workstream:product`
- `needs-interface-note`
- `needs-physical-device`
- `needs-performance-proof`
- `blocked-external`
- `release-gate`

## Milestones

| Milestone | Purpose | Exit Criteria |
|---|---|---|
| M0 - Baseline Transfer | Move current project to user's computer and GitHub safely. | Source bundle verified, private repo created, baseline tag pushed, first Codex worker can run tests. |
| M1 - Free Local Wi-Fi Stabilization | Make the free local edition reliable enough for GitHub release. | Browser/PWA works on mobile/desktop, package launches cleanly, docs are beginner-friendly, known issues listed. |
| M2 - Mobile App Shells | Prove Android and iOS app direction without destabilizing host. | App shells exist or blockers documented, pairing compatibility is mapped, store constraints are documented. |
| M3 - Paid Remote Architecture | Prove remote signaling, P2P-first flow, TURN fallback, and cost model. | Signaling contract exists, relay provider decision has pricing evidence, local free mode is independent. |
| M4 - High-Speed Native Capture | Decide and prototype native capture/encode path. | Capture spike produces benchmark evidence and recommendation; browser capture remains fallback. |
| M5 - Closed Beta Readiness | Prepare paid beta and store review. | Security/privacy docs, support diagnostics, beta checklist, release gates, and pricing assumptions exist. |

## Issue 1: Initialize Private GitHub Repo and Baseline Tag

Labels: `workstream:repo`, `release-gate`

Plan pages: Page 2, Page 3, Page 4, Page 25.

Scope:
- Initialize Git in `C:\RemoteDesktopControllerPlan\remote-control-mvp` or the copied user-computer folder.
- Commit only source, docs, tests, packaging scripts, and GitHub scaffolding.
- Tag the working baseline as `v0.1-local-wifi-baseline-v76`.
- Push `main` and the tag to a private GitHub repo.

Acceptance:
- `git status --ignored` proves excluded folders are ignored.
- `git log --oneline --decorate -1` shows the baseline commit.
- `git tag --list` shows the baseline tag.
- Remote URL is private repo URL.

## Issue 2: Make CI Match Local Validation

Labels: `workstream:repo`

Plan pages: Page 18, Page 23, Page 25.

Scope:
- Add GitHub Actions workflow for Node syntax checks and core tests.
- CI must not require screen capture, phone hardware, or local network.
- Keep physical-device gates documented separately.

Acceptance:
- Workflow exists under `.github/workflows/`.
- Workflow runs `node --check` for server and public scripts.
- Workflow runs the core Node tests that passed locally.
- Physical-device gates are listed but not faked as CI coverage.

## Issue 3: Browser/PWA Regression Lock

Labels: `workstream:browser`, `needs-physical-device`

Plan pages: Page 8, Page 11, Page 19.

Scope:
- Preserve v76 behavior: touchpad relative movement, visual recenter only, real cursor never recentered by joystick reset.
- Lock tap, double-tap, hold, scroll, edge-hold, keyboard, zoom, settings, display, and reconnect behavior.
- Make desktop browser layout usable enough for testing.

Acceptance:
- Tests or manual gates cover each gesture/state.
- Screenshots exist for portrait, landscape, and desktop browser.
- No host protocol change without interface note.

## Issue 4: Zoom and Lens Settings Finalization

Labels: `workstream:browser`, `needs-physical-device`, `needs-performance-proof`

Plan pages: Page 11, Page 16, Page 19.

Scope:
- Keep zoom lens off when toggle is off.
- Add or preserve hold-to-zoom, zoom level, and lens size settings.
- Keep the lens cursor as a small gold dot centered in the lens.
- Avoid lag spikes or duplicate overlapping zoom buttons.

Acceptance:
- Toggle on/off leaves no stale lens.
- Settings persist and sanitize correctly.
- Phone test confirms lens follows cursor and does not blank/blink.
- Performance note records whether zoom changes FPS or input smoothness.

## Issue 5: Monitor Switching and Coordinate Accuracy

Labels: `workstream:display`, `needs-physical-device`

Plan pages: Page 12, Page 16, Page 19.

Scope:
- Separate display selection, input target, capture source, and phone-visible display state.
- Add diagnostics for display bounds, scale, selected monitor, and capture source.
- Add tests for side-by-side, stacked, mixed DPI, identical resolution, laptop plus external, and reconnect.

Acceptance:
- Single-display behavior remains stable.
- Multi-monitor test cases are documented and at least logic tests pass.
- Manual physical-monitor checklist records known remaining browser-capture limits.

## Issue 6: Android App Shell Prototype

Labels: `workstream:android`, `needs-physical-device`

Plan pages: Page 9, Page 11, Page 19.

Scope:
- Scaffold Android client direction.
- Preserve current pairing/session model.
- Plan secure storage, haptics, native keyboard, orientation, and future native WebRTC.

Acceptance:
- Android scaffold builds or environment blocker is written clearly.
- Compatibility note explains how it connects to host.
- No changes to host protocol unless interface note exists.

## Issue 7: iOS App Shell Prototype

Labels: `workstream:ios`, `needs-physical-device`

Plan pages: Page 10, Page 20.

Scope:
- Scaffold iOS client direction.
- Preserve current pairing/session model.
- Plan Keychain storage, haptics, keyboard, orientation, App Store review notes, and future native WebRTC.

Acceptance:
- iOS scaffold/build note or Xcode/macOS blocker.
- App Store compliance checklist exists.
- Compatibility note explains current host expectations.

## Issue 8: Remote Signaling and TURN Cost Model

Labels: `workstream:remote`, `needs-performance-proof`

Plan pages: Page 5, Page 7, Page 14, Page 15.

Scope:
- Define account-backed remote signaling and device registry.
- Design P2P-first WebRTC flow with TURN fallback.
- Model Cloudflare/Twilio/self-host relay costs and fair-use subscription rules.

Acceptance:
- Signaling contract exists.
- TURN pricing date checked and recorded.
- Local free mode remains independent from paid backend.

## Issue 9: Native Windows Capture Spike

Labels: `workstream:capture`, `needs-performance-proof`

Plan pages: Page 6, Page 12, Page 16.

Scope:
- Research and prototype Windows native capture path.
- Compare browser capture to native capture and hardware encode possibilities.
- Measure FPS, frame time, CPU/GPU, cursor composition, and monitor identity.

Acceptance:
- Spike results and recommendation exist.
- Browser capture fallback is not removed.
- Paid remote architecture has a realistic path to high speed.

## Issue 10: Product, Pricing, Store, and Support Readiness

Labels: `workstream:product`, `release-gate`

Plan pages: Page 13, Page 14, Page 20, Page 21, Page 24.

Scope:
- Define free local GitHub edition and paid remote subscription.
- Draft pricing assumptions, privacy/data inventory, terms outline, responsible-use language, support diagnostics, and closed beta gates.

Acceptance:
- Free/paid matrix exists.
- Pricing model includes relay bandwidth assumptions.
- Store/privacy checklist exists.
- Support bundle avoids raw screen frames and typed text.

