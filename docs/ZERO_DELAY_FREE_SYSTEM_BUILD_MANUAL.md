# Zero Delay Free System Build Manual

## Page 1 - Target, Checkpoint Boundary, and Non-Negotiable Success Criteria

Checkpoint One is the rollback line. It preserves the current working `v67` local-Wi-Fi controller, including source, packaging scripts, documentation, and the ready-to-send package zip. The zero-delay build must not destroy that working version. Every major step from this point forward should be reversible. If the new system becomes unstable, ugly, confusing, or slower than the checkpoint, we return to Checkpoint One and either retry the implementation differently or ship the checkpoint as the stable local-Wi-Fi version.

The phrase "zero delay" has to be treated as a product target rather than a literal physics claim. A browser, Wi-Fi network, operating system compositor, screen capture API, video encoder, decoder, and phone display all add latency. The real target is the fastest free path that feels like a real remote desktop video feed instead of a screenshot slideshow. For this project, the free path is WebRTC video for the screen feed plus the existing WebSocket control channel for mouse, keyboard, shortcuts, pairing, monitor selection, settings, and safety. WebRTC gives hardware-accelerated browser video encoding, congestion control, jitter buffering, and frame pacing. The current screenshot loop cannot compete with that because it repeatedly captures full screenshots, compresses them as JPEGs, ships them over a socket, decodes each image, and redraws a canvas.

The build must preserve the parts that already work. The phone UI, PIN pairing, approval flow, touchpad model, keyboard bridge, settings sheet, shortcut buttons, monitor UI, local packaging, and rollback package are valuable. The rebuild should replace the live screen transport first, not throw away the whole app. The old screenshot feed should remain as a fallback mode until the new WebRTC feed proves reliable. This avoids the trap of ending with a half-built experimental version that cannot be used.

The new system has three main actors. The laptop host server remains the Node process that serves pages, handles pairing, exposes the host console, and receives phone input. The laptop browser capture page becomes a new local page that the laptop user opens and grants screen capture permission to. The phone controller receives the WebRTC video stream and sends control commands as before. This is still free, same-Wi-Fi, and accountless. The tradeoff is that the laptop user may need to click "Share screen" in the browser when starting the high-speed mode. That is acceptable because it unlocks true video-like behavior without paid infrastructure or native encoder work.

The first release of the zero-delay system should target single-screen WebRTC video first. Multi-monitor support can be layered on top after the basic video path is smooth. The existing monitor picker can initially select which logical monitor/input target receives commands, while the WebRTC browser share can show either a selected screen/window chosen in the browser prompt or the whole display. Later, we can map monitor choices more tightly by asking the user to share the matching display or by adding separate capture sessions.

The success bar is strict. When nothing is touched on the phone, a video playing on the laptop should visibly move on the phone. Moving the mouse should not be the thing that wakes the screen. The stream should not blink black. The zoom lens should not flicker. The touchpad should not cause Safari page jumps. The phone should still pair with a PIN, approve on the laptop, and stop safely. If WebRTC fails or the user does not grant capture permission, the app should clearly fall back to the current screenshot mode rather than appearing broken.

Page 1 completion goals:
- Checkpoint One remains preserved and documented as the rollback point.
- The new target is defined as free, same-Wi-Fi, browser-based WebRTC video plus existing control channel.
- Screenshot streaming remains available as fallback until WebRTC is stable.
- The build does not remove working input, pairing, keyboard, shortcut, settings, or packaging features.
- The acceptance target is live video motion without touching the mouse.

## Page 2 - Architecture and Transport Split

The zero-delay architecture splits the system into a video plane and a control plane. The video plane should use WebRTC because it is built for low-latency media. The control plane should continue using the current WebSocket protocol because it already handles authentication, command sequencing, timestamps, acknowledgements, real-input safety, and diagnostics. Mixing both planes into one protocol would make the build more fragile. Keeping them separate allows video to evolve while controls stay stable.

The Node server needs a signaling layer. WebRTC peers need to exchange offers, answers, and ICE candidates. Because this is same-Wi-Fi, we can use host-local WebSocket signaling without a paid TURN server. A STUN server may be optional for local Wi-Fi; for same LAN it often is not needed. The server should add a small signaling namespace or message type family: `rtc.hostHello`, `rtc.phoneHello`, `rtc.offer`, `rtc.answer`, `rtc.ice`, `rtc.status`, and `rtc.stop`. The signaling channel must be authorized. The laptop capture page can authenticate using the host key. The phone can authenticate using the existing paired session token.

The laptop browser capture page should be served by the same Node server. It will be opened from the host console with a clear button like "Start Low-Latency Video." It should call `navigator.mediaDevices.getDisplayMedia()` only after a user click. It should create an `RTCPeerConnection`, add the captured video track, and wait for a phone peer. When the phone connects, signaling negotiates the stream. The page should show whether capture is idle, waiting for phone, connected, failed, or stopped.

The phone controller should add a video rendering surface. The cleanest path is to use a `<video>` element for the WebRTC stream, with canvas overlay only for cursor lens, calibration targets, and optional cursor dot. The browser video element will be smoother and more power-efficient than drawing every frame manually to canvas. The current canvas can remain for screenshot fallback. The UI should not show two screens at once. There should be one display area that switches internally between WebRTC video mode and screenshot canvas fallback mode.

Input coordinates must remain accurate. In WebRTC mode, direct display touches and zoom lens mapping should use the video element's rendered rectangle and the known stream dimensions. The system needs metadata for the shared video size. The capture page can send track settings such as width, height, frameRate, displaySurface, and cursor mode through signaling or server state. The phone can then map normalized coordinates from the visible video rectangle to monitor coordinates. Until perfect monitor mapping is finished, touchpad relative movement should be the primary input mode because it does not depend on pixel-perfect video coordinates.

The server should expose clear diagnostics. Host console should show video mode: screenshot fallback, WebRTC waiting, WebRTC connected, WebRTC failed, or capture permission missing. Phone debug state should include whether the active display source is `webrtc` or `screenshot`, the incoming video resolution, peer connection state, ICE state, and last frame/render heartbeat if available. Normal users should see simple labels only.

Page 2 completion goals:
- Add an authorized WebRTC signaling channel to the Node server.
- Add a laptop capture page that starts screen sharing from a user click.
- Add a phone video receiver that displays WebRTC in the existing display area.
- Preserve screenshot canvas as fallback mode.
- Maintain the existing WebSocket control plane for input.
- Expose simple status and debug diagnostics for both video modes.

## Page 3 - Server Signaling Implementation

The server implementation should be small, explicit, and testable. It should not turn into a general-purpose WebRTC server. The job is only to match one laptop capture peer with one or more phone receiver peers on the same host session. The first version can support one active phone receiver at a time. If multiple phones connect, the server can either reject additional receivers or let the host capture page negotiate separate peer connections. For simplicity and reliability, version one should support one receiver and report "already connected" for extras.

The WebSocket upgrade handler already authenticates phone sessions. The signaling work can either reuse the existing `/ws` endpoint with new `rtc.*` message types or add a separate endpoint such as `/rtc?role=host&key=...` and `/rtc?role=phone&token=...`. A separate endpoint is cleaner because signaling messages can be routed without mixing with high-frequency input messages. The host capture peer authenticates with `HOST_KEY`; the phone peer authenticates with the session token. Both identities should be attached to a small in-memory room.

The room object should track `hostSocket`, `phoneSocket`, last offer, last answer, ICE candidates, connected timestamps, and state. It must clean up sockets on close. If the host capture page refreshes, the old host peer should be replaced. If the phone refreshes, the old phone peer should be replaced. Stale candidates should be discarded when a new negotiation starts. The server should not store media; it only relays signaling JSON.

The message schema should be validated. Every signaling message should include protocol version, type, sequence, timestamp, and payload. Offer and answer payloads should contain `sdp` and `type`. ICE payloads should contain candidate data or a null end-of-candidates marker. Unknown types should produce clear errors. The server should log state transitions but avoid noisy per-candidate logging in normal mode.

The host console API should expose RTC state. `/api/host` can include `rtcStatus` with host connected, phone connected, negotiation state, last error, active mode, and capture page URL. This lets the host page and tests know what is happening without scraping logs. The phone page can also receive RTC availability through the existing state packets or fetch it from an API.

Testing should cover authentication, routing, cleanup, replacement, and error cases. A host with a bad key must not connect. A phone without approval must not receive signaling. Offer from host should route to phone. Answer from phone should route to host. ICE should route both directions. Socket close should clear state. Replacement should not leak old sockets. These are fast Node tests and should land before browser WebRTC UI work.

Page 3 completion goals:
- Implement one-room WebRTC signaling with host-key and phone-token authentication.
- Route offer, answer, and ICE messages in both directions.
- Clean up stale peers and replace refreshed peers safely.
- Add RTC state to host diagnostics.
- Add protocol validation and focused signaling tests.

## Page 4 - Laptop Capture Page

The laptop capture page is the bridge between a free browser API and the remote controller. It should be launched from the host console and should feel simple. The page needs one primary button: "Start Low-Latency Video." When clicked, it calls `getDisplayMedia` with video enabled and audio disabled by default. Audio can be considered later, but adding audio early complicates permissions and feedback. The browser's native screen picker lets the laptop user choose a screen, window, or tab.

After capture starts, the page creates an `RTCPeerConnection`. The captured video track is added to the peer connection. The capture page connects to the signaling endpoint as the host role. When a phone receiver is present, the host creates an offer, sets local description, sends the offer through signaling, receives an answer, sets remote description, and exchanges ICE candidates. If the phone arrives first, the host should create the offer when both sides are ready. If capture stops, the host should close the peer and notify the server.

The page should show a small local preview, but not as a distracting heavy UI. The preview is useful to confirm the shared surface is correct. It should show status text: not started, asking permission, sharing, waiting for phone, connected, stopped, or failed. It should also show the current phone URL and PIN if possible, so the user does not need to jump between pages. However, the host console should remain the primary approval surface.

Capture settings should be tuned for latency. `getDisplayMedia` constraints are limited and browser-dependent, but we can request reasonable values: frame rate around 30, width/height not excessive if supported, and cursor capture if available. We should not over-constrain because that can make capture fail. The peer connection can set sender parameters with degradation preference favoring frame rate over resolution when supported. The goal is motion smoothness first.

The capture page should recover gracefully. If permission is denied, it should explain that the user needs to click Start again and choose a screen. If the video track ends because the user stops sharing, it should move to stopped state and close the peer. If the phone disconnects, it should stay ready and renegotiate when the phone returns. If WebRTC fails, it should show a clear fallback message telling the phone to use screenshot fallback.

Page 4 completion goals:
- Add `/capture` or equivalent host capture page.
- Start screen capture only from a user click.
- Create and manage the host-side RTCPeerConnection.
- Send video track to phone through WebRTC.
- Show clean status and local preview.
- Handle permission denied, track ended, phone disconnect, and renegotiation.

## Page 5 - Phone WebRTC Receiver and Display Integration

The phone receiver should feel like the same app, not a second app. The display area should become a layered component: WebRTC video when available, screenshot canvas fallback when WebRTC is unavailable, and overlays above whichever video source is active. The user should not need to understand the difference unless troubleshooting. A small Settings option can expose "Video mode: Auto / Low latency / Screenshot fallback." Auto should prefer WebRTC when connected.

The phone should create its `RTCPeerConnection` after pairing and approval. It connects to the signaling endpoint using its session token. When it receives an offer, it sets remote description, creates an answer, sets local description, and sends the answer. Incoming tracks attach to a video element. ICE candidates are exchanged as they arrive. The phone should track `connectionState`, `iceConnectionState`, video dimensions, first frame time, and last resize time.

The display element should avoid canvas painting for the main video in WebRTC mode. A video element using `playsinline`, `autoplay`, and `muted` should render the stream. On iOS Safari, `playsinline` is important. The app should call `video.play()` after attaching the stream, and if autoplay is blocked, it should show a button to resume video. Because the stream is remote screen video, it should be muted and not require audio permission.

Zoom and lens behavior need to be adapted. The full-screen zoom view can be implemented with CSS transforms or by adjusting object positioning on a wrapper, rather than forcing every video frame through canvas. The cursor lens can be approximated using CSS clipped duplicated video only if browser support and performance are acceptable. If duplicating a live video element is unreliable, lens mode can use a lightweight overlay that follows the cursor and rely on the main video zoom. The product goal is smoothness, so any lens feature that causes hitches must be optional and disabled by default in WebRTC mode.

Fallback rules must be deterministic. If WebRTC connects, hide screenshot canvas and pause screenshot streaming where possible to save CPU. If WebRTC disconnects or fails, show the last screenshot mode and request the screenshot stream again. If the phone is in screenshot fallback, current v67 behavior remains. If the laptop capture page is not started, the phone should show a clean prompt: "Start low-latency video on the laptop."

Page 5 completion goals:
- Add phone-side RTCPeerConnection and signaling.
- Render incoming stream in the existing display area with a video element.
- Prefer WebRTC in Auto mode and keep screenshot fallback available.
- Make zoom/follow behavior work without forcing video through canvas.
- Pause screenshot streaming when WebRTC video is active.
- Recover cleanly when WebRTC fails or capture is not started.

## Page 6 - Input Mapping, Cursor, Touchpad, and Drag Under WebRTC

The input system should not be rebuilt from scratch. The touchpad relative movement, single tap, double tap, long press, drag, keyboard, Ctrl, Win, Codex, Claude, and Stop controls should keep using the current command protocol. The main WebRTC task is to make sure display-relative actions, cursor overlay, and zoom follow use the correct geometry when the active display source is video rather than screenshot canvas.

Touchpad mode is the safest default. Relative movement does not require exact video-to-monitor mapping, so it should work immediately once the phone is paired. For direct display tapping or future direct cursor placement, the phone needs the video element's bounding rectangle, video resolution, object-fit calculations, viewport zoom, and selected monitor metadata. These should be encapsulated in one geometry helper instead of scattering coordinate math across the app.

The host still knows monitor geometry from `screenshot-desktop` and cursor provider data. The capture page knows the browser track settings. These two sources are not always identical. A shared browser screen might be a window or tab rather than the entire physical monitor. Therefore, the first WebRTC release should label direct touch as "best effort" unless the capture source matches the selected display. Touchpad mode should remain primary for reliable control.

Cursor overlay should prefer acknowledgements during active input, just like the current system. The visual cursor in WebRTC mode can be drawn as a DOM overlay above the video. It should not require redrawing video frames. Its position should be based on normalized monitor coordinates mapped to the video rectangle. If mapping is uncertain, the overlay can be hidden rather than misleading the user. A wrong cursor is worse than no cursor.

Dragging tabs must remain reliable. Double-tap drag should send pointer down, movement packets, and pointer up in order. The move smoothing added to the checkpoint should remain. WebRTC video should reduce perceived input lag because the screen updates independently from mouse movement. Tests should prove that no input commands are lost when video mode is active.

Page 6 completion goals:
- Keep existing WebSocket input protocol.
- Use touchpad relative movement as the default reliable control mode.
- Add WebRTC display geometry helpers for overlays and direct touch.
- Keep cursor overlay DOM-based in video mode.
- Preserve click, right click, drag, keyboard, shortcuts, and Stop behavior.
- Test command ordering while WebRTC mode is active.

## Page 7 - Performance, Quality, and Lag Reduction

Performance work must be measured rather than guessed. The current screenshot system has a measurable capture time around hundreds of milliseconds. The WebRTC system should track time to first frame, connection state changes, approximate received frame rate where available, video dimensions, freezes, and reconnects. Browser APIs expose some stats through `RTCPeerConnection.getStats()`. The app should sample stats every one or two seconds in debug state and host diagnostics.

The first performance target is smooth idle video. A video playing on the laptop must move on the phone while the touchpad is untouched. The second target is input responsiveness. Moving the cursor should appear quickly on the phone video. The third target is stability: no black blinking, no repeated reconnect loops, no UI hitches when opening Settings, and no Safari double-tap zoom.

The host capture page should prefer frame rate over resolution. Where supported, sender parameters can set `degradationPreference = "maintain-framerate"`. We can avoid huge capture constraints and let the browser encoder adapt. For local Wi-Fi, WebRTC will usually choose a reasonable bitrate. If stats show too much bandwidth or dropped frames, we can add a quality setting that requests lower resolution or frame rate.

The phone should avoid expensive work while WebRTC video is active. It should not run the screenshot stream at the same time unless fallback is active. It should not redraw canvas every 220ms if the video element is doing the rendering. Overlays should be lightweight DOM or minimal canvas. The zoom lens should be optional and should not duplicate live video if that causes hitches. The settings added in Checkpoint One for lens hold, size, and zoom should remain, but WebRTC mode may default to hold-only lens or no lens if necessary.

The app should include a performance status in debug tools, not in the main UI. Normal users should see a clean status like "Low-latency video connected." Debug can expose fps estimate, resolution, bytes received, packets lost, jitter, peer state, and fallback reason.

Page 7 completion goals:
- Add WebRTC stats sampling for received fps, resolution, jitter, packet loss, and connection state.
- Stop screenshot streaming while WebRTC video is active.
- Prefer frame rate over resolution where browser APIs allow.
- Keep overlays lightweight and avoid canvas-heavy video rendering.
- Prove idle video motion without touch input.
- Provide clear fallback reasons when low-latency mode cannot run.

## Page 8 - UI Polish and Operator Flow

The finished system needs a clean launch flow. The host console should have a visible low-latency section with three states: not started, capture page open/waiting, and connected. The call to action should be plain: "Start Low-Latency Video." Clicking it opens the capture page. The capture page asks the user to click one button and choose the screen. The phone then automatically receives the stream after pairing.

The phone UI should remain minimal. There should not be a pile of technical WebRTC words on the main screen. A small status can say "Low latency" or "Fallback." Settings can expose video mode, zoom level, lens size, lens hold, quality/fallback, and diagnostics if needed. The control rail should not gain more clutter. If a feature is diagnostic, it belongs in Settings or debug, not on the main rail.

The capture page should be visually simple and reassuring. It should show the chosen share preview, the connection state, and a stop sharing button. It should not look like a developer panel. If no phone is connected, it should say "Waiting for phone." If the phone is connected, it should say "Streaming to phone." If screen sharing stops, it should say "Sharing stopped."

Packaging must explain the new flow. The dad/fresh-install package should still start with `Start Remote Controller.bat`. The launcher can open the host console as before. The instructions should add one step: click "Start Low-Latency Video" and choose the screen if you want smooth video. If the user skips it, screenshot fallback still works. This keeps setup simple and avoids making WebRTC permission feel like a mysterious failure.

The UI should always provide an escape hatch. Stop should stop control. The capture page stop button should stop screen sharing. Closing the capture page should drop WebRTC and let the phone fall back. If the phone disconnects, the host should not stay in a confusing connected state.

Page 8 completion goals:
- Add a clean low-latency section to the host console.
- Add a clean capture page with Start, status, preview, and Stop.
- Add phone video mode status without cluttering the rail.
- Update package instructions for the new smooth-video step.
- Preserve Stop and fallback behavior.
- Avoid developer-looking WebRTC jargon in normal UI.

## Page 9 - Tests, Probes, Screenshots, and Acceptance

Testing must protect the exact bugs that have been painful. There should be a no-input video motion probe for WebRTC just like the current no-input screenshot probe. The test should connect a phone receiver, start or mock a media stream where possible, and verify that video readiness changes independently of pointer movement. Full browser WebRTC can be difficult in headless mode, so some tests may use mocked `RTCPeerConnection` and mocked `MediaStream`, while a manual browser acceptance test verifies real screen share.

Server signaling tests should be pure Node and reliable. They should cover host auth, phone auth, offer routing, answer routing, ICE routing, cleanup, replacement, and invalid message handling. Phone UI tests should prove that video mode switches the display surface to the video element and hides screenshot canvas. Fallback tests should prove that screenshot mode returns when WebRTC fails.

Browser visual tests should capture host console, capture page idle, capture page sharing mock, phone normal mode, phone low-latency video mode, settings sheet, portrait, and landscape. Screenshots should confirm there are no overlapping controls, duplicate zoom states, clipped buttons, or debug text in the main UI.

Manual acceptance is required because real `getDisplayMedia` permission prompts cannot be fully automated in normal headless tests. The manual checklist should be short and exact: start host, click low-latency video, choose display, pair phone, play a video or move a window on laptop without touching phone, confirm motion on phone, move cursor, click, drag tab, toggle zoom, rotate phone, stop capture, confirm fallback or stopped state.

Performance acceptance should record approximate observed latency and smoothness. We do not need lab-grade metrics, but we do need evidence that the phone updates continuously without input. If WebRTC is worse than screenshot fallback on a machine, fallback should remain available.

Page 9 completion goals:
- Add server signaling unit tests.
- Add phone mocked-WebRTC UI tests.
- Add fallback tests.
- Add no-input low-latency video acceptance probe or manual checklist.
- Capture visual screenshots for host, capture page, phone, settings, and landscape.
- Keep current screenshot-stream tests passing.

## Page 10 - Implementation Order, Rollback, Packaging, and Completion Rules

The implementation order must reduce risk. Step one is checkpoint preservation, already done. Step two is signaling server and tests. Step three is capture page with mocked/manual testing. Step four is phone receiver with mocked stream tests. Step five is display integration and fallback. Step six is input geometry cleanup for video mode. Step seven is diagnostics and performance stats. Step eight is UI polish. Step nine is package instruction update. Step ten is package rebuild, smoke test, and manual acceptance.

Each step should have a small rollback. If signaling breaks the existing WebSocket input channel, revert only signaling. If capture page fails, keep it hidden and leave screenshot fallback. If phone WebRTC rendering causes UI instability, gate it behind Auto/Low latency settings and default back to screenshot. The project should never be left without a working local controller because Checkpoint One exists.

Packaging should not include development tests unless needed for smoke. The ready-to-send zip should include current app source, production dependencies, start/stop launchers, fresh-install instructions, and updated low-latency instructions. It should remain easy: install Node, unzip, double-click Start, click Start Low-Latency Video if smooth video is wanted, open phone URL, enter PIN, approve.

Completion requires more than code compiling. The build is not complete until the phone shows continuous motion with no mouse movement, the mouse feels usable, zoom does not introduce blinking, settings do not overlap, host/capture/phone status is understandable, fallback works, and the package smoke test passes. If the build cannot satisfy this, we stop and return to Checkpoint One rather than pretending it is done.

The final deliverable should include a fresh zip and a short note explaining two modes: low-latency WebRTC video and screenshot fallback. The user should be able to send it to someone with a fresh Windows install and give them simple steps. The app should feel like one system, not a pile of experimental pages.

Page 10 completion goals:
- Implement in the ordered sequence: signaling, capture page, phone receiver, display integration, input mapping, stats, polish, packaging.
- Keep screenshot fallback and Checkpoint One available throughout.
- Update package instructions and rebuild the ready-to-send zip.
- Pass focused automated tests and package smoke tests.
- Manually verify continuous video motion without touching the phone.
- Ship only when the new mode is clearly better than Checkpoint One, otherwise roll back.
