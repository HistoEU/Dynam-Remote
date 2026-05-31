"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.join(__dirname, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

test("Android shell scaffold keeps host trust and WebView boundaries explicit", () => {
  const manifest = read("clients/android/app/src/main/AndroidManifest.xml");
  const mainActivity = read("clients/android/app/src/main/java/eu/histo/dynamremote/MainActivity.kt");
  const networkConfig = read("clients/android/app/src/main/res/xml/network_security_config.xml");
  const docs = read("docs/mobile/android-compatibility.md");

  assert.match(manifest, /android:allowBackup="false"/);
  assert.match(manifest, /android:usesCleartextTraffic="true"/);
  assert.match(networkConfig, /cleartextTrafficPermitted="true"/);

  assert.match(mainActivity, /allowedHostOrigin/);
  assert.match(mainActivity, /requestOrigin != null && requestOrigin == allowedHostOrigin/);
  assert.match(mainActivity, /openExternalUri\(uri\)/);
  assert.match(mainActivity, /request\.deny\(\)/);
  assert.match(mainActivity, /document\.getElementById\('disconnectBtn'\)/);

  assert.match(docs, /Host approval, pending sessions, approved sessions, session expiry, revocation, trusted-device opt-in, and free local Wi-Fi mode stay unchanged/);
  assert.match(docs, /no Gradle, Android SDK, `adb`, `sdkmanager`, emulator/);
});
