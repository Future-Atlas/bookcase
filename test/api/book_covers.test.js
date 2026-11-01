const test = require('node:test');
const assert = require('node:assert/strict');
const covers = require('../../api/book-covers');

function recorder() {
  return {
    statusCode: 200, headers: {}, body: '',
    setHeader(name, value) { this.headers[name] = value; },
    status(value) { this.statusCode = value; return this; },
    json(value) { this.body = value; return this; },
  };
}

const sample = {
  'ISBN:9784488402327': {
    bib_key: 'ISBN:9784488402327',
    thumbnail_url: 'http://books.google.com/books?id=sample&img=1&zoom=5',
    info_url: 'https://books.google.com/books?id=sample&source=gbs_ViewAPI',
  },
  'ISBN:9784413299084': {
    bib_key: 'ISBN:9784413299084',
    thumbnail_url: 'https://books.google.com/books?id=second&img=1',
    info_url: 'https://books.google.com/books?id=second',
  },
};

test('batch ISBN lookup uses official keyless Dynamic Links and supplies credit URL', async () => {
  let requestedUrl;
  const handler = covers.createHandler({ request: async (url, options) => {
    requestedUrl = new URL(url);
    assert.ok(options.signal instanceof AbortSignal);
    return {ok: true, text: async () => 'SharemariumBookCovers(' +
      JSON.stringify(sample) + ');'};
  }});
  const res = recorder();
  await handler({method: 'GET', query: {
    isbn: '9784488402327,9784413299084',
  }}, res);
  assert.equal(res.statusCode, 200);
  assert.equal(requestedUrl.hostname, 'books.google.com');
  assert.equal(requestedUrl.searchParams.get('jscmd'), 'viewapi');
  assert.equal(requestedUrl.searchParams.get('callback'), 'SharemariumBookCovers');
  assert.equal(requestedUrl.searchParams.get('bibkeys'),
    'ISBN:9784488402327,ISBN:9784413299084');
  assert.equal(res.body.covers['9784488402327'].coverUrl.startsWith('https://'), true);
  assert.equal(res.body.covers['9784488402327'].creditUrl.includes('books.google.com'), true);
  assert.equal(res.headers['Cache-Control'], 'public, max-age=0, s-maxage=300');
});

test('only exact requested ISBN editions with Google-hosted image and book link pass', () => {
  const data = {
    ...sample,
    'ISBN:9784488402327': {
      bib_key: 'ISBN:9784488402327',
      thumbnail_url: 'https://evil.example/other-cover.jpg',
      info_url: 'https://books.google.com/books?id=sample',
    },
    'ISBN:9780000000000': {
      bib_key: 'ISBN:9780000000000',
      thumbnail_url: 'https://books.google.com/books?id=unrelated&img=1',
      info_url: 'https://books.google.com/books?id=unrelated',
    },
  };
  const parsed = covers.parseDynamicLinks(
    'SharemariumBookCovers(' + JSON.stringify(data) + ');',
    ['9784488402327', '9784413299084'],
  );
  assert.deepEqual(Object.keys(parsed), ['9784413299084']);
});

test('reject JSONP injection, wrong callback, missing book link and oversized payload', () => {
  assert.throws(() => covers.parseDynamicLinks(
    'SharemariumBookCovers({});process.exit(1)', ['9784488402327'],
  ));
  assert.throws(() => covers.parseDynamicLinks(
    'notOurCallback({});', ['9784488402327'],
  ));
  assert.throws(() => covers.parseDynamicLinks(
    'SharemariumBookCovers(' + 'x'.repeat(256001) + ')',
    ['9784488402327'],
  ));
  const bad = {...sample};
  bad['ISBN:9784488402327'] = {
    ...bad['ISBN:9784488402327'], info_url: 'https://evil.example/books',
  };
  const parsed = covers.parseDynamicLinks(
    'SharemariumBookCovers(' + JSON.stringify(bad) + ')',
    ['9784488402327'],
  );
  assert.deepEqual(parsed, {});
});

test('invalid input never reaches Google (method, provider, ISBN length, injection)', async () => {
  let count = 0;
  const handler = covers.createHandler({
    request: async () => { count++; throw new Error('no'); },
  });
  for (const query of [
    {isbn: '../private'}, {isbn: '9784488402327', url: 'https://evil.example'},
    {isbn: 'bad,9784488402327'}, {isbn: Array(27).fill('9784488402327').join(',')},
  ]) {
    const res = recorder();
    await handler({method:'GET', query}, res);
    assert.equal(res.statusCode, 400);
  }
  const wrongMethod = recorder();
  await handler({method: 'POST', query:{isbn:'9784488402327'}}, wrongMethod);
  assert.equal(wrongMethod.statusCode, 405);
  assert.equal(count, 0);
});

test('rate limit and timeout are not cached as an empty cover set', async () => {
  const limited = covers.createHandler({ request: async () => ({ok:false,status:429}) });
  const res1=recorder();
  await limited({method:'GET',query:{isbn:'9784488402327'}}, res1);
  assert.equal(res1.statusCode, 503);
  assert.equal(res1.headers['Cache-Control'], 'no-store');
  assert.equal(res1.headers['Retry-After'], '5');

  const timed = covers.createHandler({ request: async () => {
    const err = new Error('slow');
    err.name = 'TimeoutError';
    throw err;
  }});
  const res2=recorder();
  await timed({method:'GET',query:{isbn:'9784488402327'}}, res2);
  assert.equal(res2.statusCode, 504);
  assert.equal(res2.headers['Cache-Control'], 'no-store');
});
