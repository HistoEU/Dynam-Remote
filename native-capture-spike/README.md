# Native Capture Spike - Worker 3

Date: 2026-05-31

## Current Evidence Boundary

This spike does not claim native capture is complete or production-ready. The current branch preserves browser/WebRTC and screenshot fallback paths. The included benchmark probe measures the existing Node capture adapter timing and metadata only; it discards captured frame buffers and writes no raw screen images.

Run:

```powershell
node benchmarks\capture-performance-probe.js --samples=12 --mode=screen
```

Useful variations:

```powershell
node benchmarks\capture-performance-probe.js --samples=12 --mode=fake
node benchmarks\capture-performance-probe.js --samples=30 --mode=screen --monitor=display-1
```

## Comparison

| Path | Strengths | Risks / gaps | Fit |
| --- | --- | --- | --- |
| Browser `getDisplayMedia` + WebRTC | Free, already works in browser, hardware encode likely available through browser, good fallback UX | Requires user permission, source identity is browser-mediated, unattended capture is not reliable, source labels are limited/sanitized | Keep as free local Wi-Fi low-latency path and fallback |
| `screenshot-desktop` | Already integrated, simple monitor list, good safe fallback | Screenshot cadence is not video-grade, CPU copies/JPEG encode cost, cursor composition is separate, monitor identity can drift by enumeration order | Keep as fallback and diagnostic baseline |
| Windows Graphics Capture | Modern Windows API, designed for frame capture, supports monitor/window capture, compatible with hardware encode pipeline | Needs native module, explicit capture item/session management, cursor and display identity must be proven on multi-monitor hardware | Recommended next paid-product spike path |
| Desktop Duplication API | Low-level desktop frames, mature for full-display capture, can pair with hardware encode | More complex, Windows desktop/session edge cases, cursor composition and HDR/DPI behavior need careful handling | Secondary path if WGC identity/performance fails |
| Hardware encode via Media Foundation / NVENC / AMF / QuickSync | Required for polished high-FPS paid remote video with lower CPU | Native integration and GPU capability matrix required, fallback encoder needed | Pair with WGC or Desktop Duplication after capture proof |

## Benchmark Fields

The probe reports:

- capture FPS
- frame time average, p95, min, and max
- average and p95 frame bytes
- CPU user/system time for the sample run
- memory RSS and heap used
- monitor identity summary
- fallback behavior
- cursor composition status
- GPU availability blocker

It does not measure GPU use, end-to-end phone latency, browser encoder stats, or real cursor composition. Those require a real browser/phone or a native Windows probe.

## Local Probe Result

Command run in this worktree:

```powershell
node benchmarks\capture-performance-probe.js --samples=5 --mode=screen
```

Observed result on this environment:

- screen capture active, no raw frames written
- 3 monitors enumerated
- selected `display-1` at `1920x1080`, landscape, scale `1`
- capture FPS: `12.72`
- average frame time: `78.62ms`
- p95 frame time: `80.9ms`
- average frame bytes: `172285`
- p95 frame bytes: `172327`
- memory RSS: `47849472` bytes
- cursor composition, GPU use, hardware encode, and phone latency were not measured by this Node probe

## Recommendation

Build the next paid high-speed proof as a small Windows-native module around Windows Graphics Capture first, with Desktop Duplication as the fallback comparison. The proof should expose stable monitor identity, frame pacing, cursor composition, and a hardware encode path before replacing any current free/fallback capture mode. Browser/WebRTC should remain the free local Wi-Fi path and fallback until native capture has measured wins on multi-monitor hardware.

## Required Real-Hardware Follow-Up

- Laptop panel plus external display.
- Two identical-resolution external displays side by side.
- Stacked display layout.
- Portrait display.
- Mixed DPI layout.
- Disconnect and reconnect of the selected display.
- Browser capture source mismatch after monitor switch.
- Cursor composition check over moving video and text editor windows.
