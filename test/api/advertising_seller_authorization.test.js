const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("ads.txt authorizes Ninja AdMax sellers without restoring the retired AdSense account", () => {
  const adsTxt = fs.readFileSync(
    path.join(__dirname, "../../web/ads.txt"),
    "utf8",
  );
  // Ninja AdMax's official reseller list contains Google exchange entries.
  // Those are not the publisher's retired AdSense account.
  assert.doesNotMatch(adsTxt, /pub-3052085512168272/i);
  assert.match(adsTxt, /^adm\\.shinobi\\.jp,232064,DIRECT\\r?$/m);
  assert.match(adsTxt, /^google\\.com,pub-[0-9]+,RESELLER(?:,[a-f0-9]+)?\\r?$/m);
});

test("production smoke accepts Ninja AdMax's authorized seller declarations", async () => {
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
  assert.match(adsTxt, /^adm\\.shinobi\\.jp,232064,DIRECT\\r?$/m);
});
