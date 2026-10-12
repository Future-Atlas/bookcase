const test = require("node:test");
const assert = require("node:assert/strict");
const rakuten = require("../../api/_rakuten_request");
const originalRequest = rakuten.requestRakuten;
const originalFetch = global.fetch;
const originalEnv = { ...process.env };
function res() { return {
  headers: {}, statusCode: 200,
  setHeader(k,v) { this.headers[k] = v; },
  status(s) { this.statusCode = s; return this; },
  send(b) { this.body = b; return this; },
}; }
function setup({ reviews = [], production = true, error = false } = {}) {
  process.env.VERCEL_ENV = production ? "production" : "preview";
  process.env.RAKUTEN_APP_ID = "test";
  process.env.RAKUTEN_ACCESS_KEY = "test";
  process.env.SUPABASE_URL = "https://example.test";
  process.env.SUPABASE_ANON_KEY = "test";
  rakuten.requestRakuten = async () => {
    if (error) throw Error("offline");
    return { ok:true, text:async () => JSON.stringify({Items:[{Item:{
      isbn:"9784101010014",title:'本<title>',author:"著者",
      itemCaption:"紹介文",publisherName:"出版社",
    }}]}) };
  };
  global.fetch = async url => {
    assert.match(String(url), /book_id=eq\.9784101010014/);
    assert.match(String(url), /profiles.is_private=eq.false/);
    return {ok:true,text:async () => JSON.stringify(reviews)};
  };
  delete require.cache[require.resolve("../../api/seo")];
  return require("../../api/seo");
}
test.afterEach(() => {
  rakuten.requestRakuten = originalRequest; global.fetch = originalFetch;
  for (const key of Object.keys(process.env)) if (!(key in originalEnv)) delete process.env[key];
  Object.assign(process.env, originalEnv);
});
test("book SEO serves title, canonical, schema and only non-spoiler reviews", async () => {
  const handler = setup({reviews:[
    {id:"public",comment:"読書感想".repeat(30),profiles:{username:"reader"}},
    {id:"spoiler",is_spoiler:true,comment:"secret".repeat(40)},
  ]});
  const out = res(); await handler({query:{path:"/book/9784101010014"}},out);
  assert.equal(out.statusCode,200);
  assert.match(out.body, /本&lt;title&gt;/);
  assert.match(out.body, /"@type":"Book"/);
  assert.match(out.body, /content="index,follow"/);
  assert.match(out.body, /https:\/\/www.sharemarium.com\/book\/9784101010014/);
  assert.doesNotMatch(out.body,/secret/);
});
test("thin book pages and all staging pages are noindex", async () => {
  for (const production of [true,false]) {
    const handler=setup({production}); const out=res();
    await handler({query:{path:"/book/9784101010014"}},out);
    assert.equal(out.statusCode,200); assert.match(out.body,/noindex/);
  }
});
test("API failures are retryable rather than a permanent missing-book response", async () => {
  const handler=setup({error:true}); const out=res();
  await handler({query:{path:"/book/9784101010014"}},out);
  assert.equal(out.statusCode,503); assert.equal(out.headers["Cache-Control"],"no-store");
});
