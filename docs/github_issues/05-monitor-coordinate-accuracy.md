# Issue 5: Monitor Switching and Coordinate Accuracy

Labels: `workstream:display`, `needs-physical-device`

Milestone: `M1 - Free Local Wi-Fi Stabilization`

Branch: `display/monitor-accuracy`

Plan pages: Page 12, Page 16, Page 19.

## Purpose

Fix the class of bugs where the phone displays one monitor while input moves another, or switching briefly shows the correct monitor then reverts. The final system needs explicit monitor identity, source lock, and coordinate mapping.

## Scope

- Separate selected input monitor, selected capture source, and visible phone display state.
- Add diagnostics for monitor bounds, scale, selected target, and capture source.
- Add tests for side-by-side, stacked, mixed DPI, laptop plus external, identical external monitors, and reconnect.
- Preserve single-display behavior.

## Owned Files

- Coordinate mapper files/tests
- Display metadata docs
- Display selector UI only if needed

## Forbidden Changes

- Do not rewrite paid backend or mobile apps.
- Do not break single-display local Wi-Fi control.
- Do not claim browser capture can fully solve monitor identity if the browser source picker is the limiting factor.

## Required Interface Contracts

- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Starter Brief

- `docs/workstreams/monitor-accuracy-and-display-switching.md`

## Acceptance Evidence

- Coordinate/display tests pass.
- Manual multi-monitor checklist exists.
- Single-display smoke still works.
- Any remaining browser-capture source limitation is documented honestly.
