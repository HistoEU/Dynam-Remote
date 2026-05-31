# Input Safety and Coordinate Mapping Contract

Source of truth:

- `src/input-adapter.js`
- `src/coordinate-mapper.js`
- `test/input-adapter.test.js`
- `test/coordinate-mapper.test.js`

## Safety Model

Real input must remain explicitly controlled by the host. Dry-run input is the safe default for code paths that do not have a native input provider or host-side approval.

Protected behavior:

- input adapter defaults to dry-run
- host can release all held mouse buttons and keys
- host can disable real input
- held keys/buttons are tracked and released cleanly
- failed input must not leave a stuck button or key without a release path

## Touchpad vs Direct Touch

Touchpad movement is relative. Direct touch is coordinate-based.

Critical invariant:

The touchpad visual dot may recenter when the user lifts their finger, but that visual recenter must never move the real cursor. This protects the bug reported by the user's brother where the real mouse got pulled back to the center.

Touchpad payloads may include visual normalized coordinates, but `mode: "touchpad"` must use `dx` and `dy` as relative movement.

Direct touch payloads may use normalized coordinates, mapped into the selected monitor bounds and scale factor.

## Monitor Coordinate Mapping

Coordinate mapping must account for:

- monitor `bounds.left`
- monitor `bounds.top`
- monitor `bounds.width`
- monitor `bounds.height`
- monitor `scaleFactor`
- side-by-side layouts
- stacked layouts
- portrait displays
- differently scaled monitors
- malformed monitor metadata fallback

Workers changing display behavior must not assume all monitors start at `(0, 0)` or share scale factor `1`.

## Monitor, Capture, and Phone-Visible State

The product must treat these as separate state:

- selected input monitor: the monitor that receives pointer/direct-touch coordinates
- requested capture source: the monitor/source requested when launching browser capture
- reported capture source: the safe source category and dimensions reported by the browser/WebRTC track
- phone-visible display: the display the phone should currently be showing

If any of these diverge, diagnostics must expose the mismatch and direct-touch behavior must remain conservative. Touchpad-relative movement remains the safest fallback because it does not depend on exact capture-to-monitor pixel identity.

## Click, Drag, Scroll, and Keyboard Invariants

Protected behavior:

- single click and double click must not be replayed by duplicate sequence
- `pointer.down` and `pointer.up` must track held button state
- `pointer.cancelDrag` must release stuck drag state
- `keyDown` and `keyUp` must track held keys
- `releaseAll` must release buttons and keys even if UI state is confused
- wheel/scroll changes must not alter cursor position unless explicitly designed and documented

## Protected Tests

Run after any input, touchpad, cursor, monitor, drag, scroll, or keyboard change:

```powershell
node --test test\input-adapter.test.js test\coordinate-mapper.test.js
```

If the change affects phone gestures, attach manual phone evidence for iPhone Safari or Android Chrome.
