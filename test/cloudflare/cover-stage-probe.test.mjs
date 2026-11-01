import test from 'node:test';
import assert from 'node:assert/strict';
import { probeCoverStage } from '../../scripts/cover-stage-probe.mjs';

const japanese = '9784488402327';
const foreign = '9780140328721';
function json(status, value) {
  return new Response(JSON.stringify(value), {
    status, headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function fakeFetch({googleStatus = 200, googleImage = true, googleUrl, creditUrl,
                    openbdStatus = 200, openbdCover = '', invalidStatus = 400} = {}) {
  return async (url) => {
    if (url.includes('isbn=not-an-isbn')) return json(invalidStatus, {error:'invalid_isbn_list'});
    if (url.includes('/api/book-covers?isbn=')) {
      if (googleStatus !== 200) return json(googleStatus, {error:'cover_lookup_unavailable'});
      return json(200, {covers: googleImage ? {
        [japanese]: {
          coverUrl: googleUrl || 'https://books.google.com/books?id=real&img=1',
          creditUrl: creditUrl || 'https://books.google.com/books?id=real',
        },
      } : {}});
    }
    if (url.includes('/api/openbd?isbn=')) {
      return openbdStatus === 200 ?
        json(200, [{summary:{isbn:japanese, cover:openbdCover}}]) :
        json(502, {error:'openbd_unavailable'});
    }
    if (url.includes('covers.openlibrary.org')) {
      return new Response(null, {status:200,headers:{'content-type':'image/jpeg'}});
    }
    throw new Error('unexpected request ' + url);
  };
}

test('staging reports image metadata without logging URLs', async () => {
  const result = await probeCoverStage('https://sharemarium-staging.example/', {
    request: fakeFetch({openbdCover:'https://example.org/jacket.jpg'}),
  });
  assert.equal(result.invalid_isbn_http, 400);
  assert.equal(result.google_api_http, 200);
  assert.equal(result.google_japanese_jacket, 'metadata_available');
  assert.equal(result.openbd_japanese_jacket, 'metadata_available');
  assert.equal(result.openlibrary_known_jacket, 'available');
  assert.ok(!JSON.stringify(result).includes('books.google.com'));
});

test('provider outages are not misreported as missing ISBN jackets', async () => {
  const result = await probeCoverStage('https://sharemarium-staging.example/', {
    request: fakeFetch({googleStatus:503, openbdStatus:502}),
  });
  assert.equal(result.google_japanese_jacket, 'upstream_unavailable');
  assert.equal(result.openbd_japanese_jacket, 'upstream_unavailable');
});

test('reject fake Google thumbnail or attribution hosts', async () => {
  for (const props of [
    {googleUrl:'https://books.google.com.evil.example/book.jpg'},
    {googleUrl:'https://books.google.com@evil.example/book.jpg'},
    {creditUrl:'https://evil.example/books?host=books.google.com'},
  ]) {
    await assert.rejects(() => probeCoverStage('https://sharemarium-staging.example/', {
      request: fakeFetch(props),
    }), /cover_probe_invalid_google_cover/);
  }
});

test('reject broken app routing and invalid base URLs', async () => {
  await assert.rejects(() => probeCoverStage('http://example.org/', {
    request: fakeFetch(),
  }), /cover_probe_invalid_origin/);
  await assert.rejects(() => probeCoverStage('https://sharemarium-staging.example/', {
    request: fakeFetch({invalidStatus:404}),
  }), /cover_probe_route_validation_failed/);
});

test('an empty valid provider result remains distinguishable from a routing failure', async () => {
  const r = await probeCoverStage('https://sharemarium-staging.example/', {
    request: fakeFetch({googleImage:false}),
  });
  assert.equal(r.google_japanese_jacket, 'not_available');
  assert.equal(r.google_api_http, 200);
});

test('malformed openBD cover URLs are classified without crashing staging checks', async () => {
  const r = await probeCoverStage('https://sharemarium-staging.example/', {
    request: fakeFetch({openbdCover:'not a url'}),
  });
  assert.equal(r.openbd_japanese_jacket, 'invalid_url');
});

test('an HTML SPA fallback cannot masquerade as a valid cover API', async () => {
  const req = async (url) => {
    if (url.includes('isbn=not-an-isbn')) return json(400, {error:'invalid_isbn_list'});
    return new Response('<html>fallback</html>', {
      status:200, headers:{'content-type':'text/html'},
    });
  };
  await assert.rejects(() => probeCoverStage('https://sharemarium-staging.example/', {
    request:req,
  }), /cover_probe_invalid_content_type/);
});
