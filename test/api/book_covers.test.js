const test = require('node:test');
const assert = require('node:assert/strict');
const covers = require('../../api/book-covers');

function recorder() {
  return {
    statusCode: 200, headers: {}, body: null,
    setHeader(name, value) { this.headers[name] = value; },
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('Google Books cover endpoint is disabled even for valid ISBNs', async () => {
  let outboundRequests = 0;
  const handler = covers.createHandler({
    request: async () => { outboundRequests += 1; throw new Error('forbidden'); },
  });
  for (const query of [
    {isbn:'9784488402327'},
    {isbn:'9784488402327,9780140328721'},
    {isbn:'malformed'},
  ]) {
    const res = recorder();
    await handler({method:'GET',query},res);
    assert.equal(res.statusCode, 410);
    assert.deepEqual(res.body, {error:'provider_disabled_pending_rights'});
    assert.equal(res.headers['Cache-Control'], 'no-store');
  }
  assert.equal(outboundRequests, 0);
});

test('disabled cover endpoint rejects writes and never accesses Google', async () => {
  let outboundRequests = 0;
  const handler = covers.createHandler({
    request: async () => { outboundRequests += 1; throw new Error('forbidden'); },
  });
  const res = recorder();
  await handler({method:'POST',query:{isbn:'9784488402327'}},res);
  assert.equal(res.statusCode, 405);
  assert.equal(res.headers.Allow,'GET');
  assert.equal(res.headers['Cache-Control'], 'no-store');
  assert.equal(outboundRequests, 0);
});
