# Issue 9: Native Windows Capture Spike

Labels: `workstream:capture`, `needs-performance-proof`

Milestone: `M4 - High-Speed Native Capture`

Branch: `host/native-capture-spike`

Plan pages: Page 6, Page 12, Page 16.

## Purpose

Investigate and prototype the native Windows capture path needed for high-speed paid remote access. Browser capture is useful as a fallback, but it is not enough for unattended, polished, low-latency remote control.

## Scope

- Compare Windows Graphics Capture, Desktop Duplication, and hardware encode options.
- Measure FPS, frame time, CPU/GPU use, cursor composition, monitor identity, and latency.
- Preserve the current Chrome/WebRTC fallback until the spike proves a better path.

## Owned Files

- New native-capture spike folder.
- Capture research docs.
- Benchmark scripts.
- Capability probes.

## Forbidden Changes

- Do not replace current capture fallback before measured proof.
- Do not rewrite phone UI.
- Do not build paid backend here.

## Required Interface Contracts

- `docs/interfaces/capture-and-video-signaling.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`

## Starter Brief

- `docs/workstreams/native-capture-and-video-performance.md`

## Acceptance Evidence

- Capture design note exists.
- Benchmark output exists or environment blocker is documented.
- Recommendation says whether to keep browser fallback, build native module, or run a deeper spike.
