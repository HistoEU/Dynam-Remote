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

## Worker 3 Implementation Notes

The branch-level model keeps these states separate:

- selected input monitor: where pointer/direct-touch coordinates are sent
- requested capture source: what the host asked the capture page/browser to share
- reported capture source: safe WebRTC/browser metadata plus actual capture size
- phone-visible display: the display the phone is expected to see from current capture metadata

Host state now includes `captureDiagnostics` with expected size, actual size, stale capture age, correction status, and divergence codes. The diagnostics are safe for host console and phone debug surfaces and do not include raw frames, raw typed text, host keys, session tokens, or raw browser window titles.

## Mixed Display Coverage

Automated tests cover:

- single display fallback behavior through existing capture adapter tests
- laptop plus external bounds
- two identical-resolution externals distinguished by bounds and source ID
- side-by-side displays
- stacked displays
- portrait displays
- mixed DPI / scale-factor direct-touch mapping
- remembered disconnected displays for reconnect diagnostics
- capture source mismatch
- stale RTC capture host after monitor switch

Manual real-monitor validation is still required for Chrome/Edge source picker identity because browsers intentionally limit exact source introspection.

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
