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
- `audioTracks`
- `audioSource`
- `microphone`
- `requestedMonitor`
- `requestedSource`
- `updatedAt`

Protected behavior:

- microphone capture must not be silently enabled
- laptop output/audio source metadata must be explicit
- requested monitor/source must be bounded strings
- capture metadata must be safe for host console and phone UI
- current Chrome/WebRTC capture remains fallback until native capture beats it with evidence

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

