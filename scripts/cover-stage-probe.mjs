// Read-only, staging-only probe for the rights-cleared cover configuration.
// Google Books endpoint must be disabled; no Open Library requests.
// openBD availability is metadata only, not proof of browser rendering.
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const sampleIsbn = '9784488402327';

function safeCoverUrl(value) {
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !!url.hostname &&
      !url.username && !url.password && !url.port;
  } catch { return false; }
}
async function requestJson(request, url) {
  return request(url, {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(15000),
  });
}
function requireJson(response) {
  if (!String(response.headers.get('content-type')).includes('application/json')) {
    throw new Error('cover_probe_invalid_content_type');
  }
}

export async function probeCoverStage(baseUrl, { request = fetch } = {}) {
  let origin;
  try { origin = new URL(baseUrl); }
  catch { throw new Error('cover_probe_invalid_origin'); }
  if (origin.protocol !== 'https:' || origin.username || origin.password ||
      origin.port || origin.pathname !== '/' || origin.search || origin.hash) {
    throw new Error('cover_probe_invalid_origin');
  }

  // Old clients must NOT be able to make Google Books calls through this API.
  const retired = await requestJson(request,
    origin.origin + '/api/book-covers?isbn=' + sampleIsbn);
  if (retired.status !== 410) throw new Error('cover_probe_google_not_disabled');
  requireJson(retired);
  const retiredBody = await retired.json();
  if (retiredBody?.error !== 'provider_disabled_pending_rights') {
    throw new Error('cover_probe_bad_disabled_response');
  }

  // The permitted openBD endpoint must still be operational and validate ISBN.
  const invalid = await requestJson(request,
    origin.origin + '/api/openbd?isbn=not-an-isbn');
  if (invalid.status !== 400) throw new Error('cover_probe_route_validation_failed');

  const openbd = await requestJson(request,
    origin.origin + '/api/openbd?isbn=' + sampleIsbn);
  if (![200, 502].includes(openbd.status)) {
    throw new Error('cover_probe_openbd_route_failed');
  }
  const result = {
    google_endpoint_http: retired.status,
    openbd_invalid_isbn_http: invalid.status,
    openbd_http: openbd.status,
  };
  if (openbd.status === 200) {
    requireJson(openbd);
    const rows = await openbd.json();
    if (!Array.isArray(rows) || rows.length !== 1 ||
        (rows[0] !== null &&
          (typeof rows[0] !== 'object' || Array.isArray(rows[0])))) {
      throw new Error('cover_probe_invalid_openbd_payload');
    }
    const summary = rows[0]?.summary;
    if (summary?.isbn && String(summary.isbn) !== sampleIsbn) {
      throw new Error('cover_probe_mismatched_openbd_isbn');
    }
    const cover = summary?.cover;
    result.openbd_japanese_jacket =
      typeof cover === 'string' && cover.trim().length ?
      (safeCoverUrl(cover.trim()) ? 'metadata_available' : 'invalid_url') :
      'not_available';
  } else {
    result.openbd_japanese_jacket = 'upstream_unavailable';
  }
  return result;
}

const invokedFile = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : '';
if (invokedFile === import.meta.url) {
  try {
    const result = await probeCoverStage(process.env.COVER_STAGE_BASE_URL || '');
    console.log('cover_stage_probe ' + JSON.stringify(result));
  } catch (error) {
    const message = error?.message || '';
    console.error(/^cover_probe_[a-z_]+$/.test(message) ?
      message : 'cover_probe_network_error');
    process.exitCode = 1;
  }
}
