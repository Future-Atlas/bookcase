const test = require("node:test");
const assert = require("node:assert/strict");
const { createHandler } = require("../../api/rakuten");

for (const endpoint of ["book", "foreign"]) {
  for (const configured of [true, false]) {
    test(endpoint + ": server owns affiliate attribution (" + configured + ")", async () => {
      let requested;
      const body = JSON.stringify({ Items: [{ Item: { affiliateUrl: "official-url" } }] });
      const handler = createHandler({
        env: {
          RAKUTEN_APP_ID: "test-app",
          RAKUTEN_ACCESS_KEY: "test-key",
          ...(configured ? { RAKUTEN_AFFILIATE_ID: " owner-id " } : {}),
        },
        request: async (url) => {
          requested = new URL(url);
          return { status: 200, text: async () => body };
        },
      });
      const res = {
        setHeader() {},
        status(code) { this.code = code; return this; },
        send(value) { this.body = value; return this; },
        json(value) { this.body = value; return this; },
      };
      await handler({ method: "GET", headers: {}, query: {
        endpoint, isbn: "9784101010014", affiliateId: "attacker-id",
      } }, res);
      assert.equal(res.code, 200);
      assert.equal(requested.searchParams.get("affiliateId"), configured ? "owner-id" : null);
      assert.equal(res.body, body);
    });
  }
}
