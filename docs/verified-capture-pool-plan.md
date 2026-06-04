# Verified Capture Pool Implementation Plan

Goal: replace fragile monitor switching through a single Chrome stream with a verified pool of capture streams, one slot per monitor.

## Problem

The current app has one RTC host peer. Monitor switching kills/relaunches the Chrome capture helper and asks Chrome to auto-select `Screen N`. That is not deterministic enough for a final product because browser display capture does not expose a hard "capture this Windows monitor id" API to normal web code.

The first monitor works because it starts once and stays stable. Switching fails because the app depends on Chrome choosing the new monitor correctly during relaunch.

## Decision

Build a capture pool:

- Each monitor has a capture slot: `display-1`, `display-2`, etc.
- Each slot can have its own capture helper process/profile.
- Each slot must prove the actual monitor it is streaming before the phone can use it.
- The phone switches between verified streams instead of forcing Chrome to switch one stream.

## Verification Rules

A stream is usable only when:

- `requestedMonitor` equals the slot monitor id.
- `verification.status` is `matched`.
- `verification.actualMonitorId` equals the slot monitor id.
- The stream is fresh.

Later hardening should add a temporary visual probe marker per monitor so identical wallpapers cannot confuse the fingerprint check.

## Architecture

### Capture Pool State

Create a server-side capture pool that tracks one slot per monitor.

Each slot stores:

- `monitorId`
- `sourceName`
- `status`: `idle`, `starting`, `alive`, `verified`, `mismatch`, `failed`, `stale`
- `peerId`
- `captureUrl`
- `lastLaunchAt`
- `lastSeenAt`
- `verification`
- `error`

### RTC Room

Extend the RTC room to support multiple host peers, not just one.

Current shape:

- one host
- one phone
- all signaling routes between those two peers

New shape:

- multiple host peers, keyed by `monitorId`
- one phone peer
- phone sends which monitor it wants
- server routes RTC offer/ICE/status from the selected verified host to the phone

The first implementation can keep one active phone RTC connection at a time. The pool still helps because the host streams are already alive and verified; phone switching only selects a different verified host peer instead of relaunching Chrome.

### Capture Helper Launching

Instead of one shared Chrome profile:

- use profile path `data/capture-browser-profile-display-1`
- use profile path `data/capture-browser-profile-display-2`
- use profile path `data/capture-browser-profile-display-3`

Each helper opens:

`/rtc?role=host&key=<hostKey>&monitor=<display-id>&source=<Screen N>&slot=<display-id>`

Each helper still uses high-quality `getDisplayMedia`.

### Phone Switching

On `monitor.select`:

- server updates `selectedMonitorId`
- server centers the real cursor on that monitor
- server checks capture pool slot for the selected monitor
- if verified, server tells phone to reconnect RTC to that monitor stream
- if not verified, server starts/repairs that slot and keeps the old visible frame until the new stream is ready

The phone must not black out during this transition.

## Files

Primary changes:

- `src/rtc-room.js`: support multiple host peers and monitor-aware routing.
- `src/server.js`: create capture pool state, launch per-monitor helpers, route monitor selection through pool.
- `public/capture.js`: include `slotMonitorId` and verification in RTC messages.
- `public/app.js`: request RTC stream for selected monitor and ignore offers from wrong monitor.

Tests:

- `test/rtc-room.test.js`: multiple host peers, route selected monitor only, preserve metadata per host.
- `test/capture-pool.test.js`: slot status, verification gating, stale/mismatch handling.
- `test/phone-connection-help.test.js`: monitor switch keeps last frame and requests selected verified stream.

## Build Order

1. Add failing RTC room tests for multiple host peers.
2. Implement minimal multi-host RTC room support.
3. Add capture pool state tests.
4. Implement capture pool state manager.
5. Wire capture helper launch paths to per-monitor profiles.
6. Wire `monitor.select` to select verified pool slot.
7. Update phone RTC request messages to include selected monitor.
8. Run targeted tests.
9. Run full `npm test`.
10. Launch live server and verify host state shows multiple capture slots.

## Non-Goals For This Pass

- Do not lower video quality to hide the bug.
- Do not rely on screenshot fallback as the main video path.
- Do not build the Electron/native capture replacement yet.
- Do not decode every hidden stream on the phone unless needed; first version can keep one active phone RTC connection.

## Acceptance Criteria

- Server can track more than one RTC host capture stream.
- Each stream is tied to a monitor slot.
- A mismatched stream is not treated as valid for a selected monitor.
- Monitor switching does not depend on a blind single-stream relaunch.
- Phone display does not clear to black during switch.
- Tests cover multi-host routing and verification gating.
