const assert = require("node:assert/strict");
const test = require("node:test");
const { createHandler } = require("../../api/staging-rakuten");

function recorder() {
  return {
    headers: {},
    statusCode: 200,
    body: null,
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    status(value) { this.statusCode = value; return this; },
    json(value) { this.body = value; return this; },
    send(value) { this.body = value; return this; },
  };
}
const env = {
  APP_ENV: "staging",
  RAKUTEN_APP_ID: "server-only-id",
  RAKUTEN_ACCESS_KEY: "server-only-access-key",
  RAKUTEN_AFFILIATE_ID: "server-only-affiliate",
  RAKUTEN_REFERER: "https://sharemarium-staging.sharemarium.workers.dev/",
};

test("staging Rakuten proxy uses server credentials and an allowlisted upstream only", async () => {
  const captured = [];
  const handler = createHandler({
    env,
    request: async (url, options) => {
      captured.push({ url, options });
      return Response.json({ Items: [{ Item: { title: "Sample" } }] });
    },
  });
  for (const [endpoint, genre, expectedPath] of [
    ["book", "001", "/BooksBook/Search/20170404"],
    ["foreign", "005", "/BooksForeignBook/Search/20170404"],
  ]) {
    const res = recorder();
    await handler({
      method: "GET",
      query: { endpoint, booksGenreId: genre, hits: "3", page: "1" },
    }, res);
    assert.equal(res.statusCode, 200);
    assert.equal(JSON.parse(res.body).Items.length, 1);
    assert.equal(res.headers["cache-control"], "public, max-age=0, s-maxage=120");
    const actual = new URL(captured.at(-1).url);
    assert.equal(actual.origin, "https://openapi.rakuten.co.jp");
    assert.ok(actual.pathname.endsWith(expectedPath));
    assert.equal(actual.searchParams.get("applicationId"), env.RAKUTEN_APP_ID);
    assert.equal(actual.searchParams.get("accessKey"), env.RAKUTEN_ACCESS_KEY);
    assert.equal(actual.searchParams.get("affiliateId"), env.RAKUTEN_AFFILIATE_ID);
    assert.equal(captured.at(-1).options.origin, env.RAKUTEN_REFERER);
    assert.ok(!res.body.includes(env.RAKUTEN_ACCESS_KEY));
  }
});

test("retailer metadata endpoint has strict query allowlist and pagination caps", async () => {
  let upstreamCalls = 0;
  const handler = createHandler({
    env,
    request: async () => { upstreamCalls++; return Response.json({ Items: [] }); },
  });
  for (const query of [
    { endpoint: "other", booksGenreId: "001" },
    { endpoint: "book", booksGenreId: "005" },
    { endpoint: "foreign", booksGenreId: "001" },
    { endpoint: "book", booksGenreId: "001", page: "101" },
    { endpoint: "book", booksGenreId: "001", hits: "31" },
    { endpoint: "book", booksGenreId: "001", hits: "0" },
    { endpoint: "book", booksGenreId: "001", page: "1.5" },
    { endpoint: "book", booksGenreId: "001", sort: "evil" },
    { endpoint: "book", booksGenreId: "001", title: "a".repeat(121) },
    { endpoint: "book", booksGenreId: "001", applicationId: "attacker" },
    { endpoint: "book", booksGenreId: "001", accessKey: "attacker" },
    { endpoint: "book", booksGenreId: "001", affiliateId: "attacker" },
    { endpoint: "book", booksGenreId: "001", constructor: "evil" },
    { endpoint: "book", booksGenreId: "001", __proto__: null, title: ["a", "b"] },
    { endpoint: "book" },
  ]) {
    const res = recorder();
    await handler({ method: "GET", query }, res);
    assert.equal(res.statusCode, 400, JSON.stringify(query));
    assert.equal(res.headers["cache-control"], "no-store");
  }
  assert.equal(upstreamCalls, 0);
});

test("production is approved while bad methods, unknown environments and missing credentials fail closed", async () => {
  const configurations = [
    [{ ...env }, "POST", 405],
    [{ ...env, APP_ENV: "preview" }, "GET", 410],
    [{ ...env, RAKUTEN_ACCESS_KEY: "" }, "GET", 503],
  ];
  for (const [candidate, method, expected] of configurations) {
    const res = recorder();
    await createHandler({
      env: candidate,
      request: async () => { throw Error("upstream should not be requested"); },
    })({ method, query: { booksGenreId: "001" } }, res);
    assert.equal(res.statusCode, expected);
  }
  const res = recorder();
  await createHandler({ env })({
    method: "GET", query: { booksGenreId: "001" },
  }, res);
  assert.equal(res.statusCode, 503);

  const production = recorder();
  await createHandler({
    env: { ...env, APP_ENV: "production" },
    request: async () => Response.json({ Items: [] }),
  })({ method: "GET", query: { booksGenreId: "001" } }, production);
  assert.equal(production.statusCode, 200);
});

test("upstream errors and queue limits are uncached and do not leak secrets", async () => {
  const handler = createHandler({
    env,
    request: async () => new Response("too_many_requests", {
      status: 429,
      headers: { "Retry-After": "5" },
    }),
  });
  const res = recorder();
  await handler({ method: "GET", query: { booksGenreId: "001" } }, res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.headers["retry-after"], "5");
  assert.equal(res.headers["cache-control"], "no-store");
  assert.deepEqual(res.body, {
    error: "rakuten_busy", upstreamStatus: 429, source: "provider",
  });
});

test("upstream errors safely distinguish quota denial from provider rejection", async () => {
  for (const [upstream, expected] of [
    [Response.json({ error: "upstream_not_allowed" }, { status: 403 }),
     { error: "rakuten_unavailable", upstreamStatus: 403, source: "quota" }],
    [Response.json({ error: "invalid_key", secret: "MUST_NOT_LEAK" }, { status: 403 }),
     { error: "rakuten_unavailable", upstreamStatus: 403, source: "provider" }],
    [Response.json({ error: "rakuten_upstream_unavailable" }, { status: 502 }),
     { error: "rakuten_unavailable", upstreamStatus: 502, source: "quota" }],
  ]) {
    const handler = createHandler({ env, request: async () => upstream });
    const res = recorder();
    await handler({ method: "GET", query: { booksGenreId: "001" } }, res);
    assert.equal(res.statusCode, 502);
    assert.deepEqual(res.body, expected);
    assert.ok(!JSON.stringify(res.body).includes("MUST_NOT_LEAK"));
  }
});

test("Rakuten 404 is a normal no-match response, not a 502 failure", async () => {
  const handler = createHandler({
    env,
    request: async () => new Response('{"error":"not_found"}', {status: 404}),
  });
  const res = recorder();
  await handler({method:"GET",query:{endpoint:"book",title:"芥川",hits:"4"}},res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { Items: [] });
  assert.equal(res.headers["cache-control"], "public, max-age=0, s-maxage=60");
  assert.ok(!JSON.stringify(res.body).includes("not_found"));
});

test("Rakuten genuine 429 is still a retryable busy response", async () => {
  const handler = createHandler({
    env,
    request: async () => new Response('{"error":"limited"}', {status:429}),
  });
  const res = recorder();
  await handler({method:"GET",query:{endpoint:"book",title:"芥川"}},res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "rakuten_busy");
});
