# Future Native Media Path

The first iOS app shell keeps `WKWebView fallback` behavior. Native media is a later milestone and must not remove the current browser/WebRTC path until measured evidence proves it is better.

## Current Fallback

The loaded web controller remains responsible for:

- `remote-controller-rtc` signaling;
- browser WebRTC receive behavior;
- screenshot/binary stream fallback;
- stream visibility messages;
- quality selection;
- capture metadata rendering.

This keeps the current local Wi-Fi product working while the iOS native shell matures.

## Native WebRTC Requirements

A native receive/decode path needs a documented host contract for:

- `remote-controller-rtc` protocol version and roles;
- offer, answer, ICE, stop, status, ping, and error message validation;
- codec and profile expectations;
- capture metadata fields: width, height, frame rate, display surface, requested monitor, requested source, audio tracks, audio source, microphone state, and updated timestamp;
- stream lifecycle: idle, waiting, ready, negotiating, connected, stopped, failed;
- fallback trigger from native WebRTC to `WKWebView` or screenshot stream;
- performance evidence: FPS, frame timing, input RTT if relevant, CPU/GPU impact, and direct vs relay path.

## Migration Rule

Native media should be feature-flagged. A future iOS worker must keep the web controller available until native receive/decode has simulator or physical-device evidence and does not weaken Stop, host approval, revoke, trusted-device boundaries, or real-input safety.
