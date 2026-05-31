# Native Capture and Video Performance Brief

Branch: `host/native-capture-spike`

Issue:

- `09-native-capture-spike.md`

Plan pages:

- Page 6: Host Capture and Video Pipeline
- Page 12: Monitor Switching and Multi-Display Accuracy
- Page 16: Performance Measurement and Optimization

## Mission

Determine the native Windows capture path needed for a high-speed paid product. Browser capture can remain the free/fallback path, but unattended low-latency remote control needs native capture, stable monitor identity, cursor composition, hardware encode, and measured frame timing.

## Owns

- new native-capture spike folder
- capture research docs
- benchmark scripts
- capability probes
- recommendation memo

## Does Not Own

- current Chrome/WebRTC fallback replacement until proven
- phone UI rewrite
- paid backend
- app store docs

## Must Read First

- `docs/interfaces/capture-and-video-signaling.md`
- `docs/interfaces/input-safety-and-coordinate-mapping.md`

## Spike Questions

Answer these with evidence:

- Can Windows Graphics Capture provide stable monitor identity?
- Is Desktop Duplication a better fit?
- How will cursor composition work?
- What encode path is realistic: Media Foundation, NVENC, AMF, QuickSync, or WebRTC native encoder?
- Can frames avoid extra CPU copies?
- What is expected FPS and frame time?
- How does it behave on laptop plus external monitor?
- Can browser capture remain fallback?

## Metrics

Capture at least:

- capture FPS
- frame time average/p95
- CPU use
- GPU use if available
- monitor ID/source stability
- cursor composition status
- rough latency compared with browser capture

## Validation

Minimum evidence:

- design note
- benchmark output or environment blocker
- recommendation: build native module, keep browser fallback only, or run deeper spike
- no removal of current capture fallback

## Done Means

The team knows the next technical step toward truly smooth paid remote video.

