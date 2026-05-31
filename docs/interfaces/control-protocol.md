# Control Protocol Contract

Source of truth:

- `src/protocol.js`
- `test/protocol.test.js`
- `src/ws.js`

## Version

Current control protocol version: `1`.

All client commands must include:

- `protocolVersion: 1`
- `type`
- positive integer `sequence`
- numeric `timestamp`
- object `payload`

The host rejects:

- missing/unsupported protocol version
- unknown type
- server-only type sent by a phone
- missing, stale, or repeated sequence
- stale or future timestamp
- non-object payload

## Client Message Types

The phone may send:

- `stream.setQuality`
- `stream.visibility`
- `acceptance.mark`
- `pointer.move`
- `pointer.click`
- `pointer.doubleClick`
- `pointer.down`
- `pointer.up`
- `pointer.cancelDrag`
- `wheel`
- `key`
- `keyDown`
- `keyUp`
- `chord`
- `text`
- `pasteText`
- `monitor.select`
- `session.disconnect`

Do not add a new client message type without updating:

- `CLIENT_MESSAGE_TYPES` in `src/protocol.js`
- relevant host handling in `src/server.js`
- phone-side sender behavior in `public/app.js`
- tests that prove validation and failure behavior
- this contract

## Server and Shared Message Types

The shared type list also includes:

- `hello`
- `state`
- `stream.frame`
- `capture.source`
- `ack`
- `error`

Phones should not send server-only types. The host should reject them with `BAD_CLIENT_TYPE`.

## Ordering and Idempotency

Phone commands are ordered by `sequence`. A command with a sequence less than or equal to the last accepted sequence is stale and should not be applied again.

Protected behavior:

- duplicate commands must not repeat clicks, keypresses, drags, or text
- reconnecting should reset sequence expectations through a fresh session
- stale-command errors must be recoverable with clear next action

## Error Contract

Errors use `makeError(code, friendly, detail, recoverable, nextAction)` and include:

- `type: "error"`
- `payload.code`
- `payload.friendly`
- `payload.detail`
- `payload.recoverable`
- `payload.nextAction`

Every new error code should have a user-useful next action in `ERROR_NEXT_ACTIONS`.

## Protected Tests

Run after any protocol change:

```powershell
node --test test\protocol.test.js
```

If a protocol change crosses host and phone, also run the relevant host/phone/browser tests and update the issue with manual phone evidence.

