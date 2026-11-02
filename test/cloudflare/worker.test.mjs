import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";

import worker, { _test } from "../../cloudflare/worker.mjs";

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

test("clean app paths are noindex in staging and on production custom domain", async () => {
  const routes = ["/login", "/mypage", "/settings", "/help", "/moderation"];
  for (const appEnv of ["staging", "production"]) {
    const { env, requests } = environment({ appEnv });
    for (const path of routes) {
      const host = appEnv === "staging" ? "staging.example.test" : "www.sharemarium.com";
      const response = await worker.fetch(new Request(`https://${host}${path}`), env);
      assert.equal(response.status, 200, path);
      assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow", path);
    }
    assert.equal(requests.length, routes.length);
  }
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

test("production custom domain adds browser security headers", async () => {
  const { env } = environment({ appEnv: "production" });
  const response = await worker.fetch(
    new Request("https://www.sharemarium.com/"),
    env,
  );

  assert.equal(
    response.headers.get("strict-transport-security"),
    "max-age=31536000",
  );
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.equal(
    response.headers.get("referrer-policy"),
    "strict-origin-when-cross-origin",
  );
  assert.match(
    response.headers.get("content-security-policy") || "",
    /frame-ancestors 'none'/,
  );
  assert.match(
    response.headers.get("content-security-policy") || "",
    /script-src-attr 'none'/,
  );
  assert.equal(
    response.headers.get("content-security-policy-report-only"),
    null,
  );
});

test("HTTP requests are permanently redirected to HTTPS", async () => {
  const { env, requests } = environment({ appEnv: "production" });
  const response = await worker.fetch(
    new Request("http://www.sharemarium.com/book/9784101269313?q=1"),
    env,
  );

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get("location"),
    "https://www.sharemarium.com/book/9784101269313?q=1",
  );
  assert.equal(requests.length, 0);
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

test("legacy book slug permanently redirects to the canonical ISBN page", async () => {
  const { env, requests } = environment({ appEnv: "production" });
  const response = await worker.fetch(
    new Request(
      "https://www.sharemarium.com/book/nanji-hoshi-no-gotoku?utm_source=google",
    ),
    env,
  );

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get("location"),
    "https://www.sharemarium.com/book/9784065281499?utm_source=google",
  );
  assert.equal(requests.length, 0);
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

  assert.equal(response.status, 410);
  assert.equal((await response.json()).error, "catalog_migrated");
  assert.equal(requests.length, 0);
});


test("Workers Free serves static Flutter assets without invoking Worker first", () => {
  const config = JSON.parse(readFileSync(new URL("../../wrangler.jsonc", import.meta.url), "utf8"));
  const patterns = config.assets.run_worker_first;
  assert.ok(Array.isArray(patterns));
  for (const route of ["/", "/api/*", "/sitemap.xml", "/robots.txt", "/login", "/mypage", "/settings", "/help", "/moderation", "/posts/*", "/book/*", "/privacy"]) {
    assert.ok(patterns.includes(route), route + " must execute the Worker for SEO/API");
  }
  assert.ok(!patterns.includes("/*"), "Worker must not run for every asset");
  assert.ok(!patterns.includes("/assets/*"), "Flutter assets should be served directly");
});

test("production workers.dev robots.txt blocks crawlers", async () => {
  const { env, requests } = environment({ appEnv: "production" });
  const response = await worker.fetch(
    new Request("https://sharemarium-production.example.workers.dev/robots.txt"),
    env,
  );
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "User-agent: *\nDisallow: /\n");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.equal(requests.length, 0);
});


test("Production deployment is main-only, manual, and checks required secrets", () => {
  const workflow = readFileSync(new URL("../../.github/workflows/deploy-cloudflare-production.yaml", import.meta.url), "utf8");
  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /\n\s*push:/);
  assert.match(workflow, /github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /inputs\.confirmation == 'DEPLOY'/);
  assert.match(workflow, /Fail closed when required production secrets are missing/);
  for (const key of ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", "SUPABASE_URL", "RAKUTEN_ACCESS_KEY"]) {
    assert.ok(workflow.includes(`secrets.${key}`), `production must validate ${key}`);
  }
});

test("named Cloudflare Workers environments explicitly publish workers.dev routes", () => {
  const config = JSON.parse(readFileSync(new URL("../../wrangler.jsonc", import.meta.url), "utf8"));
  assert.equal(config.env.staging.name, "sharemarium-staging");
  assert.equal(config.env.production.name, "sharemarium-production");
  assert.equal(config.env.staging.workers_dev, true);
  assert.equal(config.env.production.workers_dev, true);
});

test("Cloudflare staging smoke diagnostics disclose only classification codes", () => {
  const script = readFileSync(new URL("../../scripts/cloudflare-smoke.mjs", import.meta.url), "utf8");
  const workflow = readFileSync(new URL("../../.github/workflows/deploy-cloudflare-staging.yaml", import.meta.url), "utf8");
  assert.match(script, /SMOKE_DIAGNOSTIC_FILE/);
  assert.match(script, /function record\(checkName, outcome, httpStatus\)/);
  assert.doesNotMatch(script, /response\.text\(/);
  assert.doesNotMatch(script, /JSON\.stringify\(response/);
  assert.match(workflow, /cloudflare-staging-smoke-diagnostic\.json/);
  assert.match(workflow, /name: cloudflare-staging-smoke-diagnostic/);
  assert.match(workflow, /retention-days: 1/);
});

test("NDL edge cache reuses successful RSS without an extra upstream fetch", async () => {
  const entries = new Map();
  const cache = {
    async match(key) { return entries.get(key.url)?.clone(); },
    async put(key, response) { entries.set(key.url, response.clone()); },
  };
  const request = new Request("https://staging.example.test/api/ndl?dpid=ndl-boj&title=Japan&idx=1&cnt=27");
  let upstreamCalls = 0;
  const requestHandler = async () => {
    upstreamCalls++;
    return new Response("<rss><channel /></rss>", {
      status: 200,
      headers: {
        "Content-Type": "application/xml; charset=utf-8",
        "Cache-Control": "public, max-age=0, s-maxage=600",
      },
    });
  };
  const first = await _test.serveNdl(request, undefined, { cache, requestHandler });
  const second = await _test.serveNdl(request, undefined, { cache, requestHandler });
  assert.equal(first.status, 200);
  assert.equal(await first.text(), await second.text());
  assert.equal(upstreamCalls, 1);
  assert.equal(entries.size, 1);
});

test("NDL cache collapses simultaneous identical requests", async () => {
  const cache = { async match() { return undefined; }, async put() {} };
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let calls = 0;
  const request = new Request("https://staging.example.test/api/ndl?dpid=ndl-boj&title=Tokyo&cnt=27");
  const requestHandler = async () => {
    calls++;
    await gate;
    return new Response("<rss/>", {
      status: 200,
      headers: { "Content-Type": "application/xml" },
    });
  };
  const first = _test.serveNdl(request, undefined, { cache, requestHandler });
  const second = _test.serveNdl(request, undefined, { cache, requestHandler });
  release();
  const [a, b] = await Promise.all([first, second]);
  assert.equal(calls, 1);
  assert.equal(await a.text(), "<rss/>");
  assert.equal(await b.text(), "<rss/>");
});

test("NDL 504 responses are never cached and a later retry can succeed", async () => {
  const entries = new Map();
  const cache = {
    async match(key) { return entries.get(key.url)?.clone(); },
    async put(key, response) { entries.set(key.url, response.clone()); },
  };
  let attempts = 0;
  const request = new Request("https://staging.example.test/api/ndl?dpid=ndl-boj&title=Japan&cnt=27&idx=28");
  const requestHandler = async () => {
    attempts++;
    if (attempts === 1) {
      return Response.json({ error: "ndl_timeout" }, { status: 504 });
    }
    return new Response("<rss/>", {
      status: 200,
      headers: { "Content-Type": "application/xml" },
    });
  };
  assert.equal((await _test.serveNdl(request, undefined, { cache, requestHandler })).status, 504);
  assert.equal(entries.size, 0);
  assert.equal((await _test.serveNdl(request, undefined, { cache, requestHandler })).status, 200);
  assert.equal(attempts, 2);
  assert.equal(entries.size, 1);
});
