import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import worker, { _test as workerTest } from "../../cloudflare/worker.mjs";
import { guardRequest, _test } from "../../cloudflare/request-guard.mjs";

function createLimiters({ apiAllowed = true, catalogAllowed = true } = {}) {
  const calls = [];
  const env = {
    APP_ENV: "staging",
    API_RATE_LIMIT: { async limit({ key }) {
      calls.push({ name: "api", key });
      return { success: apiAllowed };
    } },
    CATALOG_RATE_LIMIT: { async limit({ key }) {
      calls.push({ name: "catalog", key });
      return { success: catalogAllowed };
    } },
    ASSETS: { async fetch() { return new Response("static"); } },
  };
  return { env, calls };
}

test("Worker rate limit bindings exist in all staging and production configs", () => {
  const settings = JSON.parse(readFileSync(
    new URL("../../wrangler.jsonc", import.meta.url), "utf8",
  ));
  const ids = new Set();
  for (const env of [settings, settings.env.staging, settings.env.production]) {
    assert.equal(env.ratelimits.length, 2);
    const general = env.ratelimits.find(x => x.name === "API_RATE_LIMIT");
    const costly = env.ratelimits.find(x => x.name === "CATALOG_RATE_LIMIT");
    assert.deepEqual(general.simple, {limit:120, period:60});
    assert.deepEqual(costly.simple, {limit:24, period:60});
    for (const limiter of env.ratelimits) {
      assert.match(limiter.namespace_id, /^[1-9][0-9]*$/);
      assert.ok(!ids.has(limiter.namespace_id), "namespaces must be separate by environment");
      ids.add(limiter.namespace_id);
    }
  }
});

test("only API and live server-rendered routes consume rate counters", () => {
  const p = _test.protectedRoute;
  assert.deepEqual(p(new Request("https://site.test/assets/app.js")), {
    protectedPath: false, costly: false,
  });
  assert.deepEqual(p(new Request("https://site.test/api/home-catalog?page=1")), {
    protectedPath: true, costly: true,
  });
  assert.deepEqual(p(new Request("https://site.test/api/openbd?isbn=9780140328721")), {
    protectedPath: true, costly: true,
  });
  assert.deepEqual(p(new Request("https://site.test/api/ndl?cnt=10")), {
    protectedPath: true, costly: true,
  });
  assert.deepEqual(p(new Request("https://site.test/api/rakuten?booksGenreId=001")), {
    protectedPath: true, costly: true,
  });
  assert.equal(p(new Request("https://site.test/api/posts-seo")).protectedPath,true);
  assert.equal(p(new Request("https://site.test/sitemap.xml")).protectedPath,true);
  assert.equal(p(new Request("https://site.test/")).protectedPath,false);
  assert.equal(p(new Request("https://site.test/"), {
    isCrawler:true,seoPath:true,
  }).protectedPath,true);
  assert.equal(p(new Request("https://site.test/posts/post-id"), {
    isCrawler:true,
  }).protectedPath,true);
  assert.equal(p(new Request("https://site.test/book/abc?seo_preview=1")).protectedPath,true);
});

test("one IP cannot bypass shared catalog quota with changing URLs", async () => {
  const {env,calls} = createLimiters();
  const headers = { "cf-connecting-ip": "203.0.113.9" };
  assert.equal(await guardRequest(new Request(
    "https://site.test/api/home-catalog?lang=jpn&topic=%E6%97%A5%E6%9C%AC&page=1", {headers}
  ),env),null);
  assert.equal(await guardRequest(new Request(
    "https://site.test/api/openbd?isbn=9780140328721", {headers}
  ),env),null);
  assert.deepEqual(calls, [
    {name:"api",key:"203.0.113.9:api"},
    {name:"catalog",key:"203.0.113.9:catalog"},
    {name:"api",key:"203.0.113.9:api"},
    {name:"catalog",key:"203.0.113.9:catalog"},
  ]);
});

test("catalog 429 is uncacheable and upstream handler is never called", async () => {
  const {env,calls} = createLimiters({catalogAllowed:false});
  const response = await worker.fetch(new Request(
    "https://site.test/api/home-catalog?lang=eng&topic=Japan&page=1",
    {headers:{"cf-connecting-ip":"198.51.100.7"}}
  ),env);
  assert.equal(response.status,429);
  assert.equal(response.headers.get("retry-after"),"60");
  assert.equal(response.headers.get("cache-control"),"no-store");
  assert.deepEqual(await response.json(),{error:"catalog_rate_limited"});
  assert.equal(calls.length,2);
});

test("generic API 429 blocks before calling a route, but static assets still work", async () => {
  const {env,calls}=createLimiters({apiAllowed:false});
  const denied=await worker.fetch(new Request(
    "https://site.test/api/rakuten?title=Japan",
  ),env);
  assert.equal(denied.status,429);
  assert.equal(calls.length,1);
  const staticAsset=await worker.fetch(new Request("https://site.test/assets/app.js"),env);
  assert.equal(staticAsset.status,200);
  assert.equal(await staticAsset.text(),"static");
  assert.equal(calls.length,1);
});

test("lost or failing limiter binding fails closed, not free-tier upstream fetch", async () => {
  const req = new Request("https://site.test/api/home-catalog?lang=jpn&topic=%E6%97%A5%E6%9C%AC&page=1");
  for(const env of [
    {APP_ENV:"staging"},
    {APP_ENV:"staging",API_RATE_LIMIT:{limit:async()=>({success:true})}},
    {APP_ENV:"staging",API_RATE_LIMIT:{limit:async()=>{throw new Error("offline")}},
      CATALOG_RATE_LIMIT:{limit:async()=>({success:true})}},
  ]) {
    const response=await worker.fetch(req,env);
    assert.equal(response.status,503);
    assert.equal(response.headers.get("cache-control"),"no-store");
    assert.equal((await response.json()).error,"rate_limit_unavailable");
  }
});

test("hostile query keys do not alter the parameter object's prototype", () => {
  const query=workerTest.queryFromUrl(new URL(
    "https://site.test/api/ndl?__proto__=malicious&constructor=attack&title=Japan",
  ));
  assert.equal(Object.getPrototypeOf(query),null);
  assert.equal(query.__proto__,"malicious");
  assert.equal(query.constructor,"attack");
  assert.equal(query.title,"Japan");
  assert.equal({}.malicious,undefined);
});


test("verified cache hit skips only expensive catalog limiter and remains generally rate limited", async () => {
  const {env, calls} = createLimiters({catalogAllowed: false});
  const request = new Request(
    "https://site.test/api/home-catalog?lang=jpn&topic=%E6%97%A5%E6%9C%AC&page=1",
    {headers: {"cf-connecting-ip": "203.0.113.77"}},
  );
  const cache = {
    async match() {
      return Response.json({books: [], rawCount: 0, hasMore: false,
        catalogSource: "openlibrary"});
    },
  };
  const hit = await workerTest.readCachedPublicCatalog(request, cache);
  assert.equal(hit?.status, 200);
  assert.equal(await guardRequest(request, env, {catalogCacheHit: !!hit}), null);
  assert.deepEqual(calls, [{name: "api", key: "203.0.113.77:api"}]);
});

test("cache flag cannot bypass catalog limiter for non-cached routes or writes", async () => {
  const {env, calls} = createLimiters({catalogAllowed: false});
  const urls = [
    "https://site.test/api/rakuten?endpoint=book",
  ];
  for (const url of urls) {
    const response = await guardRequest(new Request(url), env,
      {catalogCacheHit: true});
    assert.equal(response?.status, 429);
  }
  for (const endpoint of [
    "https://site.test/api/home-catalog?lang=jpn&topic=%E6%97%A5%E6%9C%AC&page=1",
    "https://site.test/api/openbd?isbn=9780140328721",
  ]) {
    const post = await guardRequest(new Request(endpoint, {method: "POST"}),
      env, {catalogCacheHit: true});
    assert.equal(post?.status, 429);
  }
  assert.equal(calls.filter(c => c.name === "catalog").length, 3);
});

test("Worker can serve a cached public catalog response even after catalog quota is exhausted", async () => {
  const prev = globalThis.caches;
  const responseBody = {
    books: [{id: "9784000000001", isbn: "9784000000001", title: "検証書籍",
      languageCode: "jpn"}],
    rawCount: 1, hasMore: false, catalogSource: "openlibrary",
  };
  globalThis.caches = {
    default: {
      async match() {
        return Response.json(responseBody, {
          headers: {"Content-Type": "application/json; charset=utf-8"},
        });
      },
    },
  };
  try {
    const {env, calls} = createLimiters({catalogAllowed: false});
    const req = new Request(
      "https://site.test/api/home-catalog?lang=jpn&topic=%E6%97%A5%E6%9C%AC&page=1",
    );
    const served = await worker.fetch(req, env);
    assert.equal(served.status, 200);
    assert.deepEqual(await served.json(), responseBody);
    assert.deepEqual(calls.map(call => call.name), ["api"]);

    const {env: generalBlocked} = createLimiters({
      apiAllowed: false, catalogAllowed: false,
    });
    const denied = await worker.fetch(req, generalBlocked);
    assert.equal(denied.status, 429);
    assert.deepEqual(await denied.json(), {error: "rate_limited"});
  } finally {
    if (prev === undefined) delete globalThis.caches;
    else globalThis.caches = prev;
  }
});

test("cached errors or mismatched content types never bypass the catalog limiter", async () => {
  const request = new Request(
    "https://site.test/api/home-catalog?lang=eng&topic=Japan&page=1",
  );
  for (const response of [
    Response.json({error: "catalog_source_busy"}, {status: 503}),
    new Response("<rss/>", {status: 200, headers: {"Content-Type": "application/xml"}}),
  ]) {
    const cache = {async match() {return response;}};
    assert.equal(await workerTest.readCachedPublicCatalog(request, cache), null);
    const {env, calls} = createLimiters({catalogAllowed: false});
    const blocked = await guardRequest(request, env, {catalogCacheHit: false});
    assert.equal(blocked?.status, 429);
    assert.equal(calls.filter(call => call.name === "catalog").length, 1);
  }
});


test("cached, validated openBD metadata avoids repeating the catalog quota", async () => {
  const req = new Request("https://site.test/api/openbd?isbn=9780140328721");
  const cache = {async match() {
    return Response.json([{"summary": {"isbn": "9780140328721"}}]);
  }};
  const hit = await workerTest.readCachedPublicCatalog(req, cache);
  assert.equal(hit?.status, 200);
  const {env, calls} = createLimiters({catalogAllowed: false});
  assert.equal(await guardRequest(req, env, {catalogCacheHit: !!hit}), null);
  assert.deepEqual(calls.map(item => item.name), ["api"]);
});
