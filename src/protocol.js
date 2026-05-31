"use strict";

const PROTOCOL_VERSION = 1;

const MESSAGE_TYPES = new Set([
  "hello",
  "state",
  "stream.frame",
  "stream.setQuality",
  "stream.visibility",
  "capture.source",
  "acceptance.mark",
  "pointer.move",
  "pointer.click",
  "pointer.doubleClick",
  "pointer.down",
  "pointer.up",
  "pointer.cancelDrag",
  "wheel",
  "key",
  "keyDown",
  "keyUp",
  "chord",
  "text",
  "pasteText",
  "monitor.select",
  "session.disconnect",
  "ack",
  "error"
]);

const CLIENT_MESSAGE_TYPES = new Set([
  "stream.setQuality",
  "stream.visibility",
  "acceptance.mark",
  "pointer.move",
  "pointer.click",
  "pointer.doubleClick",
  "pointer.down",
  "pointer.up",
  "pointer.cancelDrag",
  "wheel",
  "key",
  "keyDown",
  "keyUp",
  "chord",
  "text",
  "pasteText",
  "monitor.select",
  "session.disconnect"
]);

const ERROR_NEXT_ACTIONS = {
  BAD_JSON: "Refresh the phone app and reconnect to the host.",
  PAYLOAD_TOO_LARGE: "Reload the app and retry the action with a normal phone request.",
  BAD_PROTOCOL_VERSION: "Reload the phone app from the current host URL.",
  BAD_TYPE: "Update or reload the phone app so it uses the supported protocol.",
  BAD_CLIENT_TYPE: "Reload the phone app; this message is not valid from a controller.",
  BAD_SEQUENCE: "Reconnect the phone session so command ordering can reset.",
  STALE_SEQUENCE: "Ignore the duplicate command and continue with the newest phone state.",
  BAD_TIMESTAMP: "Check the phone clock, then reconnect the session.",
  STALE_TIMESTAMP: "Reconnect the phone session; an old command was rejected.",
  FUTURE_TIMESTAMP: "Check the phone clock, then reconnect the session.",
  BAD_PAYLOAD: "Reload the phone app and try the action again.",
  BAD_MONITOR: "Open Monitors and select an available display.",
  BAD_QUALITY: "Choose Fast, Balanced, Sharp, or Battery quality.",
  INPUT_DENIED: "Approve the session on the laptop and confirm the permission is enabled.",
  INPUT_FAILED: "Use Safety Release, then retry with dry-run input if needed.",
  NETWORK_NOT_ALLOWED: "Use a loopback, same-Wi-Fi, or Tailscale address from the host console.",
  BAD_HOST_KEY: "Open the host console from the trusted local URL so the host key is included.",
  BAD_SETTINGS: "Keep the host settings page open, correct the highlighted value, and save again.",
  BAD_QR_URL: "Use one of the LAN, Tailscale, or public URLs shown in the host console.",
  QR_FAILED: "Refresh the host console; if QR generation still fails, copy the URL manually.",
  SESSION_NOT_FOUND: "Forget the saved phone session, pair again with the current PIN, and approve it on the laptop.",
  SESSION_NOT_APPROVED: "Approve this phone in the laptop host console before controlling the desktop.",
  ORIGIN_NOT_ALLOWED: "Reopen the phone controller from the same URL that was used during pairing.",
  BAD_PIN: "Enter the current six-digit PIN shown in the laptop host console.",
  PIN_RATE_LIMITED: "Wait for the lockout timer, generate a fresh PIN, and try pairing again.",
  PAIR_FAILED: "Refresh the phone pairing screen and retry with the current host PIN.",
  TRUSTED_DEVICE_NOT_FOUND: "Refresh the host console and check whether that trusted phone was already removed.",
  BAD_INPUT_MODE: "Retry from the host console, then use Safety Release if input state looks stuck.",
  SAFETY_RELEASE_FAILED: "Disable real input, then use the host kill switch if any key or mouse button is stuck.",
  KILL_SWITCH_FAILED: "Close the host process from the laptop and restart it in dry-run mode.",
  NOT_FOUND: "Refresh the app from the current host URL."
};

function nowIso() {
  return new Date().toISOString();
}

function makeMessage(type, payload = {}, extra = {}) {
  if (!MESSAGE_TYPES.has(type)) {
    throw new Error(`Unknown protocol message type: ${type}`);
  }
  return {
    protocolVersion: PROTOCOL_VERSION,
    type,
    timestamp: Date.now(),
    payload,
    ...extra
  };
}

function validateClientMessage(message, options = {}) {
  if (!message || typeof message !== "object") {
    return { ok: false, code: "BAD_JSON", message: "Message must be a JSON object." };
  }
  if (message.protocolVersion !== PROTOCOL_VERSION) {
    return {
      ok: false,
      code: "BAD_PROTOCOL_VERSION",
      message: `Unsupported protocol version ${message.protocolVersion}.`
    };
  }
  if (!MESSAGE_TYPES.has(message.type)) {
    return { ok: false, code: "BAD_TYPE", message: `Unknown message type ${message.type}.` };
  }
  if (!CLIENT_MESSAGE_TYPES.has(message.type)) {
    return { ok: false, code: "BAD_CLIENT_TYPE", message: `Message type ${message.type} is not accepted from phone clients.` };
  }
  if (!Number.isSafeInteger(message.sequence) || message.sequence < 1) {
    return { ok: false, code: "BAD_SEQUENCE", message: "Client command sequence must be a positive integer." };
  }
  if (Number.isSafeInteger(options.lastSequence) && message.sequence <= options.lastSequence) {
    return { ok: false, code: "STALE_SEQUENCE", message: "Client command sequence was already handled." };
  }
  if (!Number.isFinite(message.timestamp)) {
    return { ok: false, code: "BAD_TIMESTAMP", message: "Client command timestamp is required." };
  }
  const now = Number.isFinite(options.now) ? options.now : Date.now();
  const maxAgeMs = Number.isFinite(options.maxAgeMs) ? options.maxAgeMs : 60000;
  const maxFutureMs = Number.isFinite(options.maxFutureMs) ? options.maxFutureMs : 10000;
  if (message.timestamp < now - maxAgeMs) {
    return { ok: false, code: "STALE_TIMESTAMP", message: "Client command timestamp is too old." };
  }
  if (message.timestamp > now + maxFutureMs) {
    return { ok: false, code: "FUTURE_TIMESTAMP", message: "Client command timestamp is too far in the future." };
  }
  if (message.payload !== undefined && (!message.payload || typeof message.payload !== "object" || Array.isArray(message.payload))) {
    return { ok: false, code: "BAD_PAYLOAD", message: "Client command payload must be a JSON object." };
  }
  return { ok: true };
}

function nextActionForCode(code) {
  return ERROR_NEXT_ACTIONS[code] || "Check the host console, then retry the action.";
}

function makeError(code, friendly, detail = null, recoverable = true, nextAction = null) {
  return makeMessage("error", {
    code,
    friendly,
    detail,
    recoverable,
    nextAction: nextAction || nextActionForCode(code)
  });
}

module.exports = {
  CLIENT_MESSAGE_TYPES,
  ERROR_NEXT_ACTIONS,
  MESSAGE_TYPES,
  PROTOCOL_VERSION,
  makeError,
  makeMessage,
  nowIso,
  nextActionForCode,
  validateClientMessage
};
