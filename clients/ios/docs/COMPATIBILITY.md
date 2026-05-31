# iOS Host Compatibility Notes

The iOS shell must stay compatible with the current user-owned host flow. It does not require a paid account and does not replace the browser/PWA controller contract.

## Host Discovery and Entry

MVP entry is manual paste or typing of a host URL from the host console. The accepted schemes are `http` and `https`.

Planned QR scanning should read the same host-console QR URL, require an iOS camera permission string, and never create a separate pairing path. QR support is deferred so the first scaffold does not add camera privacy review surface before a simulator or physical-device build exists.

Local paths:

- Local Wi-Fi: load the LAN phone URL from the host console.
- Tailscale: load the Tailscale URL from the host console when both devices are in the same tailnet.
- Future paid remote: use an account-backed broker only after a separate remote-signaling contract exists. The app must still keep free local Wi-Fi mode without account login.

## Pairing and Session Trust

The iOS shell loads the existing phone controller, so the current host session rules remain authoritative:

- PIN pairing uses the six-digit host PIN.
- New sessions stay pending until host approval.
- Approved sessions use the current session token and permissions.
- Trusted-device opt-in remains controlled by the existing host/PWA flow.
- A trusted-device revoke must invalidate related sessions and must be reflected on the next web controller load.
- Raw trusted-device keys must never be shown in native iOS UI.

The native shell does not bypass PIN pairing, host approval, session expiry, trusted-device revoke, or origin checks.

## Stop and Disconnect

The existing web controller Stop/disconnect control remains visible inside `WKWebView`. The native toolbar adds a Stop button that attempts to click the existing web `disconnectBtn`, stops web loading, and returns to host entry. This is a wrapper around the existing session.disconnect behavior, not a new host protocol.

Host-side Stop All Control, revoke controls, and real-input safety remain the authority for ending control and releasing held input.

## Input and Coordinate Contract

The first iOS milestone does not send native pointer or keyboard commands directly. The web controller still sends protocol version `1` messages and preserves:

- touchpad relative movement;
- direct-touch coordinate mapping;
- duplicate sequence rejection;
- held key/button release paths;
- real input disabled unless approved and enabled by the host.

Any future native input path must update the interface docs first and prove it preserves touchpad recenter safety, monitor bounds, scale factors, and Stop/release behavior.

## Browser and Capture Compatibility

`WKWebView` remains a compatibility fallback for the current browser/WebRTC and screenshot stream behavior. The iOS shell does not claim faster video or native capture. Current capture metadata and `remote-controller-rtc` signaling remain host-owned contracts.

## UX Direction

Portrait should favor host entry, PIN pairing, approval status, and thumb-friendly touchpad use after the web controller loads. Landscape should favor the captured desktop surface while keeping the native Stop control in the safe-area toolbar.

The shell uses native haptics for host save, validation failure, and clear-host actions. The current controller's keyboard sheet remains available in `WKWebView`; a future native keyboard bridge can replace it only after it proves keyDown, keyUp, chord, text, pasteText, and release behavior against the input contract.

Safe areas and notches are handled by SwiftUI navigation chrome for native controls while the web controller owns the interactive surface. Backgrounding should not create hidden control: when the user leaves the app or taps native Stop/back, the shell asks the web controller to disconnect and returns to host entry.
