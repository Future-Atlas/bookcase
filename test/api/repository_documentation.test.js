const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../..');
const read = name => fs.readFileSync(path.join(root,name),'utf8');

test('README Flutter stack matches the pinned toolchain and dependencies', () => {
  const readme = read('README.md');
  const fvm = JSON.parse(read('.fvmrc'));
  const pubspec = read('pubspec.yaml');
  assert.equal(fvm.flutter, '3.47.7');
  assert.match(readme, /Flutter 3\.47\.7/);
  assert.match(readme, /Dart SDK \^3\.13\.0/);
  assert.match(readme, /supabase_flutter \^2\.18\.0/);
  assert.match(readme, /google_fonts \^9\.0\.0/);
  assert.match(pubspec, /sdk: \^3\.13\.0/);
  assert.match(pubspec, /google_fonts: \^9\.0\.0/);
});

test('README distinguishes active Ninja advertising, staging default and retired AdSense', () => {
  const readme = read('README.md');
  assert.match(readme, /Ninja AdMax Web production/);
  assert.match(readme, /Google AdSense is not currently running/);
  assert.match(readme, /no application-imposed maximum/);
});

test('documentation acknowledges the active GitHub ruleset and missing review approval', () => {
  const rules = read('docs/github_branch_protection.md');
  assert.match(rules, /24911692/);
  assert.match(rules, /Required approval count: 0/);
  assert.match(rules, /status check context/);
});
