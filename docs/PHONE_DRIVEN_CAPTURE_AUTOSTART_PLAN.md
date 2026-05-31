# Phone-Driven Capture Autostart Plan

## Page 1 - Exact Target

The target is not "make the button better." The target is that the laptop can be left running at home, the phone can pair or reconnect from elsewhere, and the low-latency WebRTC stream starts without the user touching the laptop. The host must run one capture app, select the full desktop stream through the dedicated Chrome launch path, and keep that capture app alive enough that the phone can receive video as soon as approval and signaling are ready.

This cannot depend on the Codex in-app browser, because the in-app browser blocks or denies screen-sharing permission. The capture path must use a real local Chromium browser, preferably Chrome, launched by the host process with a dedicated profile and `--auto-select-desktop-capture-source=Entire Screen`. The capture page must be opened with `autostart=1`, and the page itself must immediately call `getDisplayMedia()` when loaded. If the browser honors the flag, it should select the entire screen without the manual picker.

The app must never open several capture windows for the same job. There should be one intended capture app instance. If the capture app is alive and heartbeating, the host should not launch another. If the capture app is stale, closed, crashed, or no longer heartbeating, the host should clear its stale RTC peer and relaunch exactly one new capture app. Manual buttons should use the same lifecycle as phone-triggered auto-start, not a separate simpler path.

## Page 2 - Lifecycle Rules

The capture lifecycle has three states: missing, starting, and alive. Missing means there is no fresh RTC host heartbeat. Starting means the server has launched Chrome recently and is waiting for the capture page to connect. Alive means the capture page is connected and sending heartbeats recently. A launch request should only spawn a browser when state is missing, or when state is starting but has exceeded a short launch timeout. Repeated clicks or repeated phone events during the starting window must return the same launch state and not spawn more windows.

The server needs explicit launch state, not just RTC state. RTC state alone is insufficient because a capture page can connect before screen sharing starts, or a stale socket can linger briefly. The server should track `captureLaunchState`: last launch timestamp, launch nonce, browser path, mode, last reason, and whether the last launch is still considered in-flight. This launch state should be included in `/api/host` so the host console can show what is happening.

Manual `Open Capture Window`, host startup auto-launch, session approval, and phone WebSocket connection should all call one function: `ensureCaptureBrowser({ reason })`. This function should decide whether to reuse the alive capture, wait for an in-flight launch, clear stale state, or spawn Chrome. That prevents split-brain behavior where one path works and another path opens duplicates.

## Page 3 - Phone-Driven Startup

Phone-driven startup happens at two moments. First, when a session is approved, the host should ensure capture is running. Second, when the phone control socket connects, the host should ensure capture is running again. This covers both first pairing and trusted/session reconnects. The reconnect path matters because if the phone is already approved but the capture app is closed, connecting from the phone should revive capture.

Host startup should also ensure capture if `autoStart` is enabled. This gives the best remote experience because the capture app is already warm before the phone arrives. If Chrome needs one-time permission or the auto-select flag fails, that failure should happen while the user is near the laptop during setup, not while the user is away. The host can still retry on phone connection later.

The capture page must send regular `rtc.ping` messages. If it is open but not sharing, the ping should include `sharing:false`. If it is sharing, it should include track width, height, frame rate, and display surface. The server should expose this metadata so the host can distinguish "capture page open but not sharing" from "full video stream should be ready."

## Page 4 - Button Behavior

The host page buttons should not feel dead. `Open Capture Window` should call the server lifecycle endpoint and always show a clear result: "capture already running," "launching capture app," "stale capture cleared and relaunched," or "Chrome not found, opened default browser." `Open Here` should be demoted to an advanced fallback because it can open in a browser context that does not support screen sharing. The preferred button should be server-launched Chrome.

The server endpoint should accept `force=1` for troubleshooting, but normal clicks should not force duplicates. Force should clear the RTC host peer and launch a new capture app. This gives a recovery path if Chrome is visibly broken. The normal path should remain conservative and single-instance.

## Page 5 - Completion Goals

- Checkpoint 2 exists before edits.
- One server function owns capture launch decisions.
- Capture launch has explicit missing/starting/alive states.
- Auto-start runs on host startup, session approval, and phone socket connection.
- Repeated manual clicks do not open duplicate capture windows.
- Stale capture state is cleared and relaunched.
- Capture page heartbeats expose whether it is actually sharing.
- Host console explains the capture lifecycle plainly.
- Tests cover duplicate-launch prevention, stale relaunch, and forced relaunch.
- Package smoke passes after implementation.
