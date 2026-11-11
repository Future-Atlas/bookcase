const test = require("node:test");
const assert = require("node:assert/strict");
const {
  readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync,
} = require("node:fs");
const { tmpdir } = require("node:os");
const { dirname, join } = require("node:path");
const { pathToFileURL } = require("node:url");

const root = join(__dirname, "../..");
const read = (relative) => readFileSync(join(root, relative), "utf8");

test("all Flutter Web release and CI pipelines self-host CanvasKit", () => {
  const workflows = [
    ".github/workflows/ci.yaml",
    ".github/workflows/cloudflare-validate.yaml",
    ".github/workflows/deploy-cloudflare-staging.yaml",
    ".github/workflows/deploy-cloudflare-production.yaml",
    ".github/workflows/deploy-staging.yaml",
    ".github/workflows/deploy.yaml",
  ];
  for (const path of workflows) {
    const content = read(path);
    assert.match(content, /^\s*run: flutter build web --release --no-web-resources-cdn/m, path);
    assert.match(content, /^\s*run: node scripts\/verify-local-canvaskit\.mjs/m, path);
    assert.doesNotMatch(content, /FLUTTER_WEB_RENDERER=html/, path);
  }
});

test("strict Cloudflare and Vercel CSPs do not allow gstatic scripts", () => {
  const worker = read("cloudflare/worker.mjs");
  const vercel = read("vercel.json");
  for (const content of [worker, vercel]) {
    assert.match(content, /script-src 'self'/);
    assert.doesNotMatch(content, /script-src[^;"\n]*https:\/\/www\.gstatic\.com/);
  }
});

test("post-deploy smoke checks local CanvasKit JS and Wasm, not just the SPA HTML", () => {
  const smoke = read("scripts/cloudflare-smoke.mjs");
  assert.match(smoke, /"canvaskit_chromium_js", "\/canvaskit\/chromium\/canvaskit\.js"/);
  assert.match(smoke, /"canvaskit_chromium_wasm", "\/canvaskit\/chromium\/canvaskit\.wasm"/);
  assert.match(smoke, /contentType: "application\/wasm", staticAsset: true/);
  assert.match(smoke, /!staticAsset && !String\(response\.headers\.get/);
});

test("build artifact verification rejects absent files and CDN-backed bootstrap", async () => {
  const script = pathToFileURL(join(root, "scripts/verify-local-canvaskit.mjs")).href;
  const { verifyLocalCanvasKit } = await import(script);
  const dir = mkdtempSync(join(tmpdir(), "sharemarium-canvaskit-"));
  try {
    assert.throws(() => verifyLocalCanvasKit(dir), /missing a nonempty local asset/);
    const files = [
      "index.html",
      "flutter_bootstrap.js",
      "canvaskit/canvaskit.js",
      "canvaskit/canvaskit.wasm",
      "canvaskit/chromium/canvaskit.js",
      "canvaskit/chromium/canvaskit.wasm",
    ];
    for (const fileName of files) {
      const file = join(dir, fileName);
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, "test");
    }
    assert.throws(() => verifyLocalCanvasKit(dir), /not configured for local CanvasKit/);
    writeFileSync(
      join(dir, "flutter_bootstrap.js"),
      'window._flutter.buildConfig = {"useLocalCanvasKit":true};',
    );
    assert.equal(verifyLocalCanvasKit(dir), files.length);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
