import test from 'node:test';
import assert from 'node:assert/strict';
import { probeCoverStage } from '../../scripts/cover-stage-probe.mjs';

const isbn = '9784488402327';
const json = (status, value) => new Response(JSON.stringify(value), {
  status, headers: { 'content-type': 'application/json; charset=utf-8' },
});

function fakeFetch({ retiredStatus = 410, retiredBody, invalidStatus = 400,
                     openbdStatus = 200, openbdCover = '',
                     openbdIsbn = isbn } = {}) {
  const outbound = [];
  const request = async (input) => {
    const url = new URL(input);
    outbound.push(url);
    if (url.hostname !== 'sharemarium-staging.example') {
      throw new Error('unexpected third-party request');
    }
    if (url.pathname === '/api/book-covers') {
      return json(retiredStatus, retiredBody || {
        error:'provider_disabled_pending_rights',
      });
    }
    if (url.pathname === '/api/openbd') {
      if (url.searchParams.get('isbn') === 'not-an-isbn') {
        return json(invalidStatus, {error:'invalid_isbn_list'});
      }
      return openbdStatus === 200 ?
        json(200, [{summary:{isbn:openbdIsbn, cover:openbdCover}}]) :
        json(openbdStatus, {error:'openbd_unavailable'});
    }
    throw new Error('unexpected API path');
  };
  return { request, outbound };
}

test('staging verifies Google Books is disabled and openBD is available', async () => {
  const mock = fakeFetch({openbdCover:'https://cover.openbd.jp/book.jpg'});
  const result = await probeCoverStage('https://sharemarium-staging.example/', mock);
  assert.equal(result.google_endpoint_http, 410);
  assert.equal(result.openbd_invalid_isbn_http, 400);
  assert.equal(result.openbd_http, 200);
  assert.equal(result.openbd_japanese_jacket, 'metadata_available');
  assert.equal(mock.outbound.length, 3);
  assert.ok(mock.outbound.every(u => u.hostname === 'sharemarium-staging.example'));
});

test('missing cover is not confused with provider outage', async () => {
  const absent = await probeCoverStage('https://sharemarium-staging.example/',
    fakeFetch());
  assert.equal(absent.openbd_japanese_jacket, 'not_available');
  const outage = await probeCoverStage('https://sharemarium-staging.example/',
    fakeFetch({openbdStatus:502}));
  assert.equal(outage.openbd_japanese_jacket, 'upstream_unavailable');
});

test('retired endpoint must return 410 with a known response', async () => {
  for (const props of [
    {retiredStatus:200},
    {retiredStatus:503},
    {retiredBody:{error:'covers_available'}},
  ]) {
    await assert.rejects(
      () => probeCoverStage('https://sharemarium-staging.example/',fakeFetch(props)),
      /cover_probe_google_not_disabled|cover_probe_bad_disabled_response/,
    );
  }
});

test('reject invalid origin and API routes', async () => {
  await assert.rejects(
    () => probeCoverStage('http://sharemarium-staging.example/',fakeFetch()),
    /cover_probe_invalid_origin/);
  await assert.rejects(
    () => probeCoverStage('https://sharemarium-staging.example/',
      fakeFetch({invalidStatus:404})),
    /cover_probe_route_validation_failed/);
});

test('bad publisher cover URL is not considered available', async () => {
  const result = await probeCoverStage('https://sharemarium-staging.example/',
    fakeFetch({openbdCover:'javascript:alert(1)'}));
  assert.equal(result.openbd_japanese_jacket, 'invalid_url');
});

test('mismatched ISBN and invalid content type are rejected', async () => {
  await assert.rejects(
    () => probeCoverStage('https://sharemarium-staging.example/',
      fakeFetch({openbdIsbn:'9780140328721'})),
    /cover_probe_mismatched_openbd_isbn/);
  const fake = fakeFetch();
  const original = fake.request;
  fake.request = async (url) => {
    const parsed = new URL(url);
    if (parsed.pathname === '/api/book-covers') {
      return new Response('<html>SPA fallback</html>',{
        status:410,headers:{'content-type':'text/html'},
      });
    }
    return original(url);
  };
  await assert.rejects(
    () => probeCoverStage('https://sharemarium-staging.example/',fake),
    /cover_probe_invalid_content_type/);
});
