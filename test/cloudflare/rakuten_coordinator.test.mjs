import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { RakutenCoordinator } from "../../cloudflare/rakuten-coordinator.mjs";

function makeCoordinator() {
  const state = new Map();
  const ctx = {
    storage: {
      async get(key) { return state.get(key); },
      async put(key, value) { state.set(key, value); },
    },
  };
  return new RakutenCoordinator(ctx, {
    RAKUTEN_APP_ID: "test-app",
    RAKUTEN_ACCESS_KEY: "test-key",
  });
}

function request({ title = "same", appId = "test-app", accessKey = "test-key", path = "BooksBook/Search" } = {}) {
  const url = new URL(`https://openapi.rakuten.co.jp/services/api/${path}/20170404`);
  url.searchParams.set("applicationId", appId);
  url.searchParams.set("accessKey", accessKey);
  url.searchParams.set("title", title);
  return new Request("https://rakuten-quota.internal/request", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ url: url.toString(), origin: "https://www.sharemarium.com/" }),
  });
}

test("coordinator validates credential ownership and blocks untrusted endpoints", async () => {
  const coordinator = makeCoordinator();
  assert.equal((await coordinator.fetch(request({ appId: "another-app" }))).status, 403);
  assert.equal((await coordinator.fetch(request({ accessKey: "stolen" }))).status, 403);
  assert.equal((await coordinator.fetch(request({ path: "Unauthorized/Path" }))).status, 403);
  assert.equal((await coordinator.fetch(new Request("https://internal/", { method: "GET" }))).status, 405);
});

test("identical requests are coalesced and a successful response is cached", async () => {
  const coordinator = makeCoordinator();
  const oldFetch = global.fetch;
  let hits = 0;
  global.fetch = async () => {
    hits++;
    return new Response('{"Items":[]}', { status: 200, headers: { "Content-Type": "application/json" } });
  };
  try {
    const [a, b] = await Promise.all([
      coordinator.fetch(request()),
      coordinator.fetch(request()),
    ]);
    assert.equal(a.status, 200);
    assert.equal(b.status, 200);
    assert.equal(hits, 1);
    assert.equal((await coordinator.fetch(request())).status, 200);
    assert.equal(hits, 1);
  } finally {
    global.fetch = oldFetch;
  }
});

test("different requests share an application-wide start interval", async () => {
  const coordinator = makeCoordinator();
  const oldFetch = global.fetch;
  const startedAt = [];
  global.fetch = async () => {
    startedAt.push(Date.now());
    return new Response('{"Items":[]}', { status: 200 });
  };
  try {
    const [first, second] = await Promise.all([
      coordinator.fetch(request({ title: "first" })),
      coordinator.fetch(request({ title: "second" })),
    ]);
    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(startedAt.length, 2);
    assert.ok(startedAt[1] - startedAt[0] >= 1000, "outbound requests must be separated by >=1 second");
  } finally {
    global.fetch = oldFetch;
  }
});

test("upstream 429 produces a persisted backoff without caching the failure", async () => {
  const coordinator = makeCoordinator();
  const oldFetch = global.fetch;
  let hits = 0;
  global.fetch = async () => {
    hits++;
    return new Response('{"error":"limited"}', {
      status: 429,
      headers: { "Retry-After": "60" },
    });
  };
  try {
    assert.equal((await coordinator.fetch(request())).status, 429);
    const response = await coordinator.fetch(request({ title: "new" }));
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("retry-after"), "60");
    assert.equal(hits, 1);
  } finally {
    global.fetch = oldFetch;
  }
});

test("Wrangler binds the SQLite coordinator to staging and production", () => {
  const config = JSON.parse(readFileSync("wrangler.jsonc", "utf8"));
  for (const section of [config, config.env.staging, config.env.production]) {
    assert.deepEqual(section.durable_objects.bindings, [
      { name: "RAKUTEN_QUOTA", class_name: "RakutenCoordinator" },
    ]);
    assert.ok(section.migrations.some((x) => x.new_sqlite_classes?.includes("RakutenCoordinator")));
  }
});

test("the Worker never sends an upstream Rakuten request without the binding", () => {
  const source = readFileSync("cloudflare/worker.mjs", "utf8");
  assert.match(source, /rakuten_quota_unavailable/);
  assert.match(source, /RAKUTEN_QUOTA\.idFromName\(appId\)/);
  assert.match(source, /export \{ RakutenCoordinator \}/);
});
