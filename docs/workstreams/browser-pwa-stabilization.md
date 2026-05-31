# Browser/PWA Stabilization Brief

Branch: `browser/pwa-polish`

Issues:

- `03-browser-pwa-regression-lock.md`
- `04-zoom-lens-settings.md`

Plan pages:

- Page 8: Browser/PWA Version Repair
- Page 11: Input, Gesture, and UX Finalization
- Page 16: Performance Measurement and Optimization
- Page 19: UI Polish and Product Feel

## Mission

Make the browser/PWA controller reliable on phone and usable on desktop without destabilizing the host. This workstream is about protecting the existing local Wi-Fi product while cleaning up the controls that users actually feel: touchpad, tap, double tap, hold, scroll, zoom, keyboard, display, settings, reconnect, and portrait/landscape layout.

## Owns

- `public/app.js`
- `public/styles.css`
- browser/PWA UI tests if added
- phone/browser manual checklist docs

## Does Not Own

- `src/server.js` protocol behavior unless an interface note is written first
- session trust and approval semantics
- paid remote backend
- native capture replacement
- package launcher behavior

## Must Read First

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/settings-schema.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Protected Behaviors

- The real cursor must not recenter when the touchpad visual dot recenters.
- Touchpad mode must remain relative.
- Direct touch mode must map through monitor bounds and scale factor.
- Display-stage pan and zoom are local visual transforms over a black background; two-finger display gestures must not send host input.
- Duplicate/stale commands must not replay clicks or keys.
- Zoom off must remove the lens and stale overlays.
- Keyboard toggle must not break native mobile keyboard.
- Landscape must keep a usable control surface.
- Video should continue updating without requiring mouse movement.
- Debug counters should stay out of normal UI unless a diagnostics mode is explicitly opened.

## First Implementation Slice

1. Read current UI state in `public/app.js`.
2. Identify touchpad, zoom, keyboard, settings, display, and reconnect state variables.
3. Add a small regression note or test around the visual-dot-vs-real-cursor invariant.
4. Stabilize one behavior at a time; do not rewrite the entire UI.
5. Attach screenshots for portrait, landscape, and desktop.

## Validation

Run:

```powershell
node --check public\app.js
node --test test\input-adapter.test.js test\coordinate-mapper.test.js test\settings-store.test.js
```

Manual gates:

- iPhone Safari portrait
- iPhone Safari landscape
- Android Chrome if available
- desktop browser
- zoom toggle on/off
- two-finger free pan that pushes the screen partly off the phone viewport into black background
- deep focal pinch zoom around the gesture point
- two-finger scroll
- edge-hold movement
- keyboard button

## Done Means

The browser/PWA feels boringly reliable on local Wi-Fi and does not create regressions in host approval, real input safety, capture fallback, or packaging.
