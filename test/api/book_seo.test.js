const test = require("node:test");
const assert = require("node:assert/strict");

function response() {
  return {
    statusCode: 200, headers: {}, body: "",
    setHeader(k, v) { this.headers[k] = v; },
    status(code) { this.statusCode = code; return this; },
    send(value) { this.body = value; return this; },
  };
}
const originalFetch = global.fetch;
const originalEnv = {...process.env};
const isbn = "9784101010014";
const sample = `<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><item>
<title>一般小説</title><dc:creator>著者</dc:creator>
<dc:identifier xsi:type="dcndl:ISBN" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">9784101010014</dc:identifier>
</item></channel></rss>`;

function setup({ xml = sample, reviews = [], featured = [], offline = false } = {}) {
  process.env.VERCEL_ENV = "production";
  process.env.SUPABASE_URL = "https://example.supabase.co";
  process.env.SUPABASE_ANON_KEY = "test";
  delete process.env.RAKUTEN_APP_ID;
  delete process.env.RAKUTEN_ACCESS_KEY;
  global.fetch = async url => {
    const target = String(url);
    if (target.includes("ndlsearch.ndl.go.jp/api/opensearch")) {
      if (offline) throw Error("offline");
      return { ok: true, status: 200, text: async () => xml };
    }
    if (target.includes("featured_books?")) return {
      ok: true, text: async () => JSON.stringify(featured)
    };
    if (target.includes("posts?")) return {
      ok: true, text: async () => JSON.stringify(reviews)
    };
    throw Error("Unexpected url: " + target);
  };
  delete require.cache[require.resolve("../../api/seo")];
  const seo = require("../../api/seo");
  return async path => {
    const res = response();
    await seo({ query: {path} }, res);
    return res;
  };
}
test.afterEach(() => {
  global.fetch = originalFetch;
  for (const key of Object.keys(process.env)) if (!(key in originalEnv)) delete process.env[key];
  Object.assign(process.env, originalEnv);
});

test("crawler book metadata uses NDL without Rakuten credentials", async () => {
  const handler = setup({reviews: [{
    id: "review", comment: "ユーザーが書いた読書の感想です。".repeat(30),
    profiles: { username: "reader", is_private: false, is_suspended: false }
  }]});
  const out = await handler("/book/" + isbn);
  assert.equal(out.statusCode, 200);
  assert.match(out.body, /一般小説/);
  assert.match(out.body, /"@type":"Book"/);
  assert.match(out.body, /index,follow/);
  assert.doesNotMatch(out.body, /楽天ブックス提供の情報/);
});

test("age restricted NDL book is not shown to anonymous crawlers", async () => {
  const handler = setup({xml:sample.replace("一般小説", "成人向け小説")});
  const out = await handler("/book/" + isbn);
  assert.equal(out.statusCode, 404);
});

test("existing public reviews survive catalog failure", async () => {
  const handler = setup({offline:true,reviews:[{
    id:"review",comment:"読後の感想です。".repeat(30),
    profiles:{username:"reader",is_private:false,is_suspended:false}
  }]});
  const out = await handler("/book/" + isbn);
  assert.equal(out.statusCode,200);
  assert.match(out.body,/読後の感想/);
  assert.equal(out.headers["Cache-Control"],"no-store");
});

test("catalog outage without reviews is retryable", async () => {
  const handler = setup({offline:true});
  const out = await handler("/book/" + isbn);
  assert.equal(out.statusCode,503);
});
