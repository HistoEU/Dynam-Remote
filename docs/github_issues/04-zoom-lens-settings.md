# Issue 4: Zoom and Lens Settings Finalization

Labels: `workstream:browser`, `needs-physical-device`, `needs-performance-proof`

Milestone: `M1 - Free Local Wi-Fi Stabilization`

Branch: `browser/pwa-polish`

Plan pages: Page 11, Page 16, Page 19.

## Purpose

Finish the zoom experience so it feels intentional instead of glitchy. The zoom lens must follow the cursor cleanly, hide completely when disabled, and expose settings without creating duplicate buttons or lag spikes.

## Scope

- Keep zoom lens off when toggle is off.
- Preserve or add hold-to-zoom.
- Preserve or add zoom level and lens size settings.
- Keep lens cursor as a small gold dot centered in the lens.
- Avoid duplicate overlapping zoom buttons.
- Measure whether zoom hurts FPS or input smoothness.

## Owned Files

- `public/app.js`
- UI settings storage tests if needed
- Browser/phone acceptance checklist

## Forbidden Changes

- Do not alter host capture protocol without interface note.
- Do not hide the zoom feature instead of fixing its states.
- Do not make zoom mandatory for normal screen viewing.

## Required Interface Contracts

- `docs/interfaces/control-protocol.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/settings-schema.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Starter Brief

- `docs/workstreams/browser-pwa-stabilization.md`

## Acceptance Evidence

- Toggle off removes lens and stale overlays.
- Toggle on shows a clean lens centered on/near cursor as designed.
- Hold-to-zoom behavior is documented and tested manually.
- Lens size/level settings persist and sanitize.
- Performance note records observed FPS/smoothness impact.
