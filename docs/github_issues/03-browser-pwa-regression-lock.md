# Issue 3: Browser/PWA Regression Lock

Labels: `workstream:browser`, `needs-physical-device`

Milestone: `M1 - Free Local Wi-Fi Stabilization`

Branch: `browser/pwa-polish`

Plan pages: Page 8, Page 11, Page 19.

## Purpose

Stabilize the browser/PWA controller on mobile and desktop without breaking the working local Wi-Fi baseline. This issue protects the behaviors that users already tested: pairing, approval, real input, touchpad movement, keyboard, zoom, capture viewing, and reconnect.

## Scope

- Preserve relative touchpad movement.
- Ensure the touchpad visual dot can recenter without moving the real cursor.
- Lock tap, double-tap, hold, two-finger scroll, edge-hold movement, keyboard, display, settings, zoom, and reconnect behavior.
- Make desktop browser layout usable enough for testing.

## Owned Files

- `public/app.js`
- `public/styles.css` if present
- Browser/UI tests
- Phone UI documentation

## Forbidden Changes

- Do not edit `src/server.js` protocol without an interface note.
- Do not alter pairing/security/session behavior.
- Do not remove the current Chrome/WebRTC capture fallback.

## Required Interface Contracts

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/settings-schema.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Starter Brief

- `docs/workstreams/browser-pwa-stabilization.md`

## Acceptance Evidence

- Tests or manual gates cover each gesture/state.
- Screenshots exist for portrait, landscape, and desktop browser.
- Manual phone checklist names device, browser, network, and result.
- No host protocol changes unless an interface note is attached.
