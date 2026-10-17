import assert from "node:assert/strict";
import test from "node:test";

import worker from "../../cloudflare/worker.mjs";

function environment({ appEnv = "staging", assetStatus = 200 } = {}) {
  const requests = [];
  return {
    env: {
      APP_ENV: appEnv,
      ASSETS: {
        async fetch(request) {
          requests.push(request.url);
          return new Response("flutter-shell", {
            status: assetStatus,
            headers: { "Content-Type": "text/html" },
          });
        },
      },
    },
    requests,
  };
}

test("staging serves Flutter SPA assets with noindex headers", async () => {
  const { env, requests } = environment();
  const response = await worker.fetch(
    new Request("https://staging.example.test/book/9784101269313"),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "flutter-shell");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.deepEqual(requests, [
    "https://staging.example.test/book/9784101269313",
  ]);
});

test("staging robots.txt blocks all crawlers without loading assets", async () => {
  const { env, requests } = environment();
  const response = await worker.fetch(
    new Request("https://staging.example.test/robots.txt"),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "User-agent: *\nDisallow: /\n");
  assert.equal(requests.length, 0);
});

test("production workers.dev hostname remains excluded from indexing", async () => {
  const { env } = environment({ appEnv: "production" });
  const response = await worker.fetch(
    new Request("https://sharemarium-production.example.workers.dev/book/123?q=1"),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
});

test("legacy profile route keeps the identifier when redirecting", async () => {
  const { env } = environment({ appEnv: "production" });
  const response = await worker.fetch(
    new Request("https://www.sharemarium.com/user/reader-1"),
    env,
  );

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get("location"),
    "https://www.sharemarium.com/users/reader-1",
  );
});

test("crawler legal requests use server-rendered HTML", async () => {
  const { env, requests } = environment({ appEnv: "production" });
  const response = await worker.fetch(
    new Request("https://www.sharemarium.com/privacy", {
      headers: { "User-Agent": "Googlebot/2.1" },
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.match(await response.text(), /プライバシーポリシー/);
  assert.equal(requests.length, 0);
});

test("API routes do not fall through to Flutter assets", async () => {
  const { env, requests } = environment();
  const response = await worker.fetch(
    new Request("https://staging.example.test/api/rakuten?title=test"),
    env,
  );

  assert.equal(response.status, 500);
  assert.equal((await response.json()).error, "rakuten_credentials_missing");
  assert.equal(requests.length, 0);
});
