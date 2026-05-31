const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');

test('CI workflow runs the full protected Worker 1 core test subset', () => {
  const workflow = fs.readFileSync(
    path.join(root, '.github', 'workflows', 'ci.yml'),
    'utf8'
  );
  const requiredTests = [
    'test\\protocol.test.js',
    'test\\settings-store.test.js',
    'test\\session-store.test.js',
    'test\\coordinate-mapper.test.js',
    'test\\input-adapter.test.js',
    'test\\rtc-room.test.js',
    'test\\capture-adapter.test.js'
  ];

  for (const requiredTest of requiredTests) {
    assert.match(workflow, new RegExp(requiredTest.replace(/\\/g, '\\\\')));
  }
});

test('source transfer audit returns actionable JSON when the zip is missing', () => {
  const missingZip = path.join(
    os.tmpdir(),
    `remote-controller-missing-${Date.now()}.zip`
  );
  const result = spawnSync(
    'powershell',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      path.join(root, 'scripts', 'audit-source-transfer-bundle.ps1'),
      '-ZipPath',
      missingZip
    ],
    {
      cwd: root,
      encoding: 'utf8'
    }
  );

  assert.notEqual(result.status, 0);
  const audit = JSON.parse(result.stdout);

  assert.equal(audit.status, 'missing');
  assert.equal(path.basename(audit.zipPath), path.basename(missingZip));
  assert.match(audit.message, /source transfer zip is not present/i);
  assert.match(audit.nextAction, /package or copy/i);
});

test('user setup verifier runs native commands by exit code instead of warning text', () => {
  const script = fs.readFileSync(
    path.join(root, 'scripts', 'verify-user-computer-setup.ps1'),
    'utf8'
  );

  assert.match(script, /System\.Diagnostics\.ProcessStartInfo/);
  assert.match(script, /RedirectStandardError\s*=\s*\$true/);
  assert.match(script, /ExitCode/);
});

test('QA runner executes root tests only and prepares screenshot output', () => {
  const script = fs.readFileSync(
    path.join(root, 'scripts', 'run-qa.ps1'),
    'utf8'
  );

  assert.match(script, /Join-Path \$root "test"/);
  assert.match(script, /output\\playwright/);
  assert.doesNotMatch(script, /& \$NodePath --test 2>&1/);
});

test('completion audit self-test passes when fresh-clone evidence gaps are explicit', () => {
  const result = spawnSync(
    'powershell',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      path.join(root, 'scripts', 'completion-audit.ps1'),
      '-SelfTest'
    ],
    {
      cwd: root,
      encoding: 'utf8'
    }
  );

  assert.equal(result.status, 0, result.stdout || result.stderr);
  const auditSelfTest = JSON.parse(result.stdout);

  assert.equal(auditSelfTest.ok, true);
  assert.equal(auditSelfTest.actualStatus, 'not-complete');
  assert.ok(auditSelfTest.failedIds.includes('PHYSICAL-001'));
  assert.ok(auditSelfTest.failedIds.includes('PHYSICAL-002'));
  assert.ok(auditSelfTest.failedIds.includes('PHYSICAL-003'));
});
