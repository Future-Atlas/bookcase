const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("ads.txt never advertises the retired AdSense account", () => {
  const adsTxt = fs.readFileSync(
    path.join(__dirname, "../../web/ads.txt"),
    "utf8",
  );
  assert.doesNotMatch(adsTxt, /pub-3052085512168272|google\.com\s*,\s*pub-/);
  assert.match(adsTxt, /Advertising disabled pending Ninja AdMax/);
});

test("production smoke accepts the disabled-advertising placeholder", async () => {
  const { smokeChecksForProfile } = await import(
    "../../scripts/production-smoke.mjs"
  );
  const adsTxt = fs.readFileSync(
    path.join(__dirname, "../../web/ads.txt"),
    "utf8",
  );
  const check = smokeChecksForProfile("production").find(
    (candidate) => candidate.path === "/ads.txt",
  );
  assert.ok(check);
  assert.match(adsTxt, check.bodyPattern);
});
