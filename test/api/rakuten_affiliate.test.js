const test = require("node:test");
const assert = require("node:assert/strict");
const { createHandler } = require("../../api/rakuten");

test("Rakuten Books API cannot issue affiliate-tagged catalog requests anymore", async () => {
  const handler = createHandler({
    env: { RAKUTEN_APP_ID: "test", RAKUTEN_ACCESS_KEY: "test", RAKUTEN_AFFILIATE_ID: "test" },
    request: async () => { throw Error("should not be called"); },
  });
  const res = {
    statusCode: 200,
    setHeader() {},
    status(value) { this.statusCode=value; return this; },
    json(value) { this.body=value; return this; },
  };
  await handler({method:"GET",query:{isbn:"9784101010014"},headers:{}},res);
  assert.equal(res.statusCode,410);
  assert.equal(res.body.error,"catalog_migrated");
});
