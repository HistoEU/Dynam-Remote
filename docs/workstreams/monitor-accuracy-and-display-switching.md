# Monitor Accuracy and Display Switching Brief

Branch: `display/monitor-accuracy`

Issue:

- `05-monitor-coordinate-accuracy.md`

Plan pages:

- Page 12: Monitor Switching and Multi-Display Accuracy
- Page 16: Performance Measurement and Optimization

## Mission

Fix the class of bugs where input moves on one monitor while the phone displays another, or switching briefly works then reverts. The solution should separate input target, capture source, visible phone state, monitor bounds, and display identity.

## Owns

- coordinate mapping tests
- monitor metadata docs
- display diagnostics
- display selector UI only if needed

## Does Not Own

- paid backend
- Android/iOS scaffolds
- unrelated UI polish
- replacing capture pipeline

## Must Read First

- `docs/interfaces/input-safety-and-coordinate-mapping.md`
- `docs/interfaces/capture-and-video-signaling.md`

## Display Cases

Cover these cases:

- single display
- laptop plus one external
- two externals side by side
- stacked displays
- mixed DPI
- portrait display
- identical resolution monitors
- display disconnect/reconnect
- browser capture source mismatch

## Diagnostic Fields

Expose or log safely:

- selected input monitor
- selected capture source
- phone-visible display label
- monitor bounds
- scale factor
- capture requested source
- capture reported source
- last switch time

## Validation

Run:

```powershell
node --test test\coordinate-mapper.test.js test\input-adapter.test.js
```

Manual gate:

- switch display
- move cursor
- click taskbar or known target on selected monitor
- verify phone display and real cursor agree

## Done Means

Single display remains stable and multi-monitor behavior has real diagnostics plus tests, even if browser capture source limitations remain documented.

