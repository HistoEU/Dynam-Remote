"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const iosRoot = path.resolve(__dirname, "..");

function readText(relativePath) {
  return fs.readFileSync(path.join(iosRoot, relativePath), "utf8");
}

test("iOS shell scaffold keeps source-controlled app and review docs together", () => {
  const requiredFiles = [
    "DynamRemote.xcodeproj/project.pbxproj",
    "DynamRemote/DynamRemoteApp.swift",
    "DynamRemote/ContentView.swift",
    "DynamRemote/HostEntryView.swift",
    "DynamRemote/ControllerWebView.swift",
    "DynamRemote/KeychainStore.swift",
    "DynamRemote/HostSessionStore.swift",
    "DynamRemote/Info.plist",
    "docs/BUILD_NOTES.md",
    "docs/COMPATIBILITY.md",
    "docs/APP_STORE_REVIEW_NOTES.md",
    "docs/PRIVACY_AND_KEYCHAIN.md",
    "docs/FUTURE_NATIVE_MEDIA.md",
    "README.md"
  ];

  for (const relativePath of requiredFiles) {
    assert.ok(fs.existsSync(path.join(iosRoot, relativePath)), `${relativePath} should exist`);
  }
});

test("iOS docs preserve existing host trust and free local Wi-Fi contracts", () => {
  const compatibility = readText("docs/COMPATIBILITY.md");
  const review = readText("docs/APP_STORE_REVIEW_NOTES.md");
  const privacy = readText("docs/PRIVACY_AND_KEYCHAIN.md");
  const nativeMedia = readText("docs/FUTURE_NATIVE_MEDIA.md");
  const readme = readText("README.md");

  assert.match(compatibility, /PIN pairing/i);
  assert.match(compatibility, /host approval/i);
  assert.match(compatibility, /Stop/i);
  assert.match(compatibility, /revoke/i);
  assert.match(compatibility, /trusted-device/i);
  assert.match(compatibility, /local Wi-Fi/i);
  assert.match(compatibility, /haptics/i);
  assert.match(compatibility, /keyboard/i);
  assert.match(compatibility, /safe-area/i);
  assert.match(review, /user-owned host/i);
  assert.match(review, /hidden surveillance/i);
  assert.match(privacy, /raw screen frames/i);
  assert.match(privacy, /raw typed text/i);
  assert.match(nativeMedia, /remote-controller-rtc/i);
  assert.match(nativeMedia, /WKWebView fallback/i);
  assert.match(readme, /Hybrid SwiftUI \+ WKWebView/i);
});
