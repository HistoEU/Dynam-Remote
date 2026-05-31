# Interface Contracts

These contracts protect shared behavior while multiple Codex instances work in parallel. Read the relevant contract before editing shared protocol, host state, capture/video, settings, session trust, input mapping, or mobile client behavior.

The rule is simple: a worker may add compatible behavior inside its owned boundary, but changing a shared contract requires an interface note, tests, and a handoff update.

## Contracts

- [Control Protocol](control-protocol.md)
- [Input Safety and Coordinate Mapping](input-safety-and-coordinate-mapping.md)
- [Session Trust and Pairing](session-trust-and-pairing.md)
- [Settings Schema](settings-schema.md)
- [Capture and Video Signaling](capture-and-video-signaling.md)

## When a Worker Must Write an Interface Note

Write an interface note before doing any of these:

- adding, renaming, or removing a WebSocket message type
- changing `protocolVersion`, RTC version, or message validation rules
- changing command sequence, timestamp, stale-command, or recoverability behavior
- changing how touchpad movement maps to real cursor movement
- changing monitor coordinate interpretation, display bounds, or scale-factor mapping
- changing pairing, approval, trusted-device, revoke, or PIN rate-limit behavior
- changing settings keys, defaults, sanitization, or persistence
- changing capture metadata sent between host, capture page, phone, and host console
- changing free local mode so it depends on account login or paid remote infrastructure

## Interface Note Template

Create a short Markdown note under `docs/interfaces/notes/`:

```markdown
# Interface Note: <short title>

Branch:
Issue:
Owner:
Date:

## Existing Contract

What the current contract says and which tests prove it.

## Proposed Change

Exact message fields, settings keys, metadata fields, endpoint behavior, or UI states that change.

## Compatibility Plan

How old clients/hosts behave, what fallback exists, and whether a feature flag is required.

## Tests and Evidence

Automated tests, package smoke, phone test, multi-monitor test, performance evidence, or screenshots required.

## Rollback

How to return to the previous contract without losing unrelated work.
```

Do not use an interface note as permission to do broad rewrites. It is a small contract-change record so the next Codex instance does not unknowingly break the same boundary.

