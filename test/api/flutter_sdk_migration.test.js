const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const read = (name) =>
  fs.readFileSync(path.join(__dirname, "../..", name), "utf8");

test("Flutter version stays aligned across local, CI, Android and release builds", () => {
  const target = "3.47.7";
  const fvm = JSON.parse(read(".fvmrc"));
  assert.equal(fvm.flutter, target);
  for (const name of [
    ".github/workflows/ci.yaml",
    ".github/workflows/android-validate.yaml",
    ".github/workflows/deploy-staging.yaml",
    ".github/workflows/deploy.yaml",
    ".github/workflows/supabase-deploy.yaml",
  ]) {
    assert.match(read(name), /flutter-version:\s*"3\.47\.7"/, name);
    assert.doesNotMatch(read(name), /flutter-version:\s*"3\.44\.9"/);
  }
  assert.match(read(".github/workflows/android-validate.yaml"), /flutter build apk --debug/);
});

test("Dart 3.13 and previously blocked dependencies are locked together", () => {
  const yaml = read("pubspec.yaml");
  const lock = read("pubspec.lock");
  assert.match(yaml, /^\s+sdk: \^3\.13\.0$/m);
  assert.match(yaml, /^\s+google_fonts: \^9\.0\.0$/m);
  assert.match(yaml, /^\s+xml: \^7\.1\.0$/m);
  assert.match(lock, /^  dart: ">=3\.13\.0 <4\.0\.0"$/m);
  assert.match(lock, /^  flutter: ">=3\.47\.0"$/m);
  for (const [name, version] of [
    ["google_fonts", "9.0.0"],
    ["xml", "7.1.0"],
    ["petitparser", "7.1.0"],
    ["material_ui", "1.6.0"],
    ["cupertino_ui", "1.1.2"],
  ]) {
    const block = lock.match(
      new RegExp("^  " + name + ":\\n([\\s\\S]*?)(?=^  [a-z0-9_]+:|^sdks:)", "m"),
    );
    assert.ok(block, "Missing " + name + " lock entry");
    assert.ok(block[1].includes('version: "' + version + '"'), "Wrong " + name + " version");
  }
  assert.match(read(".github/workflows/ci.yaml"), /git diff --exit-code -- pubspec\.lock/);
});
