const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const packageDir = path.join(root, 'packaging', 'local-wifi');

test('local Wi-Fi package script references files that exist', () => {
  const script = fs.readFileSync(
    path.join(packageDir, 'package-local-wifi.ps1'),
    'utf8'
  );
  const manifestMatch = script.match(/\$packageFiles\s*=\s*@\(([\s\S]*?)\)/);
  assert.ok(manifestMatch, 'expected $packageFiles manifest');
  const referencedFiles = Array.from(
    manifestMatch[1].matchAll(/"([^"]+)"/g),
    (match) => match[1]
  );

  assert.ok(referencedFiles.length > 0, 'expected packaging file references');

  for (const file of referencedFiles) {
    assert.ok(
      fs.existsSync(path.join(packageDir, file)),
      `missing packaging file: ${file}`
    );
  }
});

test('package smoke script exists for the package:smoke npm command', () => {
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(root, 'package.json'), 'utf8')
  );
  const smokeCommand = packageJson.scripts['package:smoke'];

  assert.match(smokeCommand, /packaging[\\/]local-wifi[\\/]smoke-local-wifi\.ps1/);
  assert.ok(
    fs.existsSync(path.join(packageDir, 'smoke-local-wifi.ps1')),
    'missing smoke-local-wifi.ps1'
  );
});

test('package smoke script saves timestamped and latest JSON reports', () => {
  const smokeScript = fs.readFileSync(
    path.join(packageDir, 'smoke-local-wifi.ps1'),
    'utf8'
  );

  assert.match(smokeScript, /package-smoke-\$Stamp\.json/);
  assert.match(smokeScript, /package-smoke-latest\.json/);
});
