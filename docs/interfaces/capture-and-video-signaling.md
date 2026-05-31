# Capture and Video Signaling Contract

Source of truth:

- `src/rtc-room.js`
- `src/capture-adapter.js`
- `public/capture.js`
- `public/app.js`
- `public/host.js`
- `test/rtc-room.test.js`
- `test/capture-adapter.test.js`
- `test/phone-binary-stream.test.js`

## RTC Signaling

Current RTC protocol:

- protocol: `remote-controller-rtc`
- version: `1`
- roles: `host`, `phone`

Host may send:

- `rtc.ready`
- `rtc.offer`
- `rtc.ice`
- `rtc.stop`
- `rtc.status`
- `rtc.ping`

Phone may send:

- `rtc.ready`
- `rtc.answer`
- `rtc.ice`
- `rtc.stop`
- `rtc.status`
- `rtc.ping`

Do not add or remove RTC message types without updating validation, routing, tests, and this contract.

## Capture Metadata

Host capture metadata is sanitized into:

- `sharing`
- `width`
- `height`
- `frameRate`
- `displaySurface`
- `reportedSource`
- `audioTracks`
- `audioSource`
- `microphone`
- `requestedMonitor`
- `requestedSource`
- `connectionState`
- `iceConnectionState`
- `firstFrameTimeMs`
- `staleCaptureAgeMs`
- `fallbackReason`
- `updatedAt`

Protected behavior:

- microphone capture must not be silently enabled
- laptop output/audio source metadata must be explicit
- requested monitor/source must be bounded strings
- reported source must be a safe browser/source category, not a raw window title or frame content
- connection, ICE, first-frame, stale-age, and fallback fields must be diagnostics only
- capture metadata must be safe for host console and phone UI
- current Chrome/WebRTC capture remains fallback until native capture beats it with evidence

## Display Identity Diagnostics

The host state may expose a sanitized `captureDiagnostics` object to make monitor/capture divergence explicit. It separates:

- `selectedInputMonitor`: monitor currently receiving real or dry-run input
- `requestedCapture`: monitor/source the host asked the capture page to share
- `reportedCapture`: browser/WebRTC-reported source class and actual video size
- `phoneVisibleDisplay`: display the phone is expected to be showing
- `expectedSize`: selected monitor bounds used for coordinate/capture comparison
- `actualSize`: active browser/WebRTC capture size
- `correction`: capture source auto-detect status, reason, last check time, correction count, and manual-action flag
- `staleCapture`: whether the current RTC host metadata is older than the freshness window
- `divergence`: safe string codes for mismatches such as requested-monitor mismatch, capture-size mismatch, stale RTC host, missing capture host, or disconnected selected monitor

These diagnostics must not include raw screen frames, typed text, session tokens, host keys, or raw browser window/tab titles.

## Room State

RTC room public state includes:

- `available`
- `state`
- `negotiationId`
- `updatedAt`
- `lastError`
- `hostConnected`
- `phoneConnected`
- clean host peer
- clean phone peer

States include practical lifecycle values such as idle, waiting, ready, negotiating, connected, stopped, and failed.

## Performance Contract

Any worker claiming video speed improvement must provide evidence:

- capture FPS
- frame timing
- first frame time
- stale capture age
- input RTT if relevant
- direct vs relay path if remote
- CPU/GPU impact where available
- device/browser used

Do not call a feed "real-time" solely because clicks work. A video feed must continue updating when the mouse is not moving.

## Native Capture Future

Native capture work should live behind a spike or feature flag until it proves:

- stable monitor identity
- cursor composition
- frame pacing
- hardware encode/decode path
- fallback to current browser capture

## Protected Tests

Run after capture or RTC signaling changes:

```powershell
node --test test\rtc-room.test.js test\capture-adapter.test.js test\phone-binary-stream.test.js
```

Attach physical-device or browser-capture evidence for changes involving Chrome screen sharing, phone display, audio, or multi-monitor behavior.
