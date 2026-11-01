// Narrow, read-only staging diagnostic for ISBN-exact book covers.
// Upstream outages and missing jackets are observations, not deploy failures.
// Invalid app routing, malformed response shapes and unsafe URLs ARE failures.
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const sampleIsbn = '9784488402327'; // Japanese edition sampled in the catalog migration
const knownOpenLibraryIsbn = '9780140328721';

function providerUrl(value, allowedHosts) {
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password &&
      !url.port && allowedHosts.includes(url.hostname);
  } catch {
    return false;
  }
}

async function requestWithDeadline(request, url, { timeoutMs = 15000, method = 'GET' } = {}) {
  return request(url, {
    method,
    redirect: 'follow',
    signal: AbortSignal.timeout(timeoutMs),
    headers: method === 'GET' ? { Accept: 'application/json' } : undefined,
  });
}

function expectJson(response) {
  if (!String(response.headers.get('content-type')).includes('application/json')) {
    throw new Error('cover_probe_invalid_content_type');
  }
}

export async function probeCoverStage(baseUrl, { request = fetch } = {}) {
  const origin = new URL(baseUrl);
  if (origin.protocol !== 'https:' || origin.username || origin.password ||
      origin.port || origin.pathname !== '/' || origin.search || origin.hash) {
    throw new Error('cover_probe_invalid_origin');
  }

  const outcome = {};
  const invalid = await requestWithDeadline(request,
    origin.origin + '/api/book-covers?isbn=not-an-isbn');
  outcome.invalid_isbn_http = invalid.status;
  if (invalid.status !== 400) throw new Error('cover_probe_route_validation_failed');

  const isbnQuery = sampleIsbn + ',' + knownOpenLibraryIsbn;
  const google = await requestWithDeadline(request,
    origin.origin + '/api/book-covers?isbn=' + isbnQuery);
  outcome.google_api_http = google.status;
  if (![200, 502, 503, 504].includes(google.status)) {
    throw new Error('cover_probe_google_route_failed');
  }
  if (google.status === 200) {
    expectJson(google);
    const body = await google.json();
    if (!body || typeof body !== 'object' || Array.isArray(body) ||
        !body.covers || typeof body.covers !== 'object' ||
        Array.isArray(body.covers)) {
      throw new Error('cover_probe_invalid_google_payload');
    }
    for (const [isbn, record] of Object.entries(body.covers)) {
      if (![sampleIsbn, knownOpenLibraryIsbn].includes(isbn) ||
          !record || typeof record !== 'object' || Array.isArray(record) ||
          !providerUrl(record.coverUrl, ['books.google.com', 'books.googleusercontent.com']) ||
          !providerUrl(record.creditUrl, ['books.google.com'])) {
        throw new Error('cover_probe_invalid_google_cover');
      }
    }
    outcome.google_japanese_jacket = body.covers[sampleIsbn] ? 'metadata_available' : 'not_available';
    outcome.google_openlibrary_sample = body.covers[knownOpenLibraryIsbn] ? 'metadata_available' : 'not_available';
  } else {
    outcome.google_japanese_jacket = 'upstream_unavailable';
    outcome.google_openlibrary_sample = 'upstream_unavailable';
  }

  const openbd = await requestWithDeadline(request,
    origin.origin + '/api/openbd?isbn=' + sampleIsbn);
  outcome.openbd_http = openbd.status;
  if (![200, 502].includes(openbd.status)) {
    throw new Error('cover_probe_openbd_route_failed');
  }
  if (openbd.status === 200) {
    expectJson(openbd);
    const records = await openbd.json();
    if (!Array.isArray(records) || records.length !== 1 ||
        (records[0] !== null && (typeof records[0] !== 'object' ||
        Array.isArray(records[0])))) {
      throw new Error('cover_probe_invalid_openbd_payload');
    }
    const summary = records[0]?.summary;
    if (summary?.isbn && String(summary.isbn) !== sampleIsbn) {
      throw new Error('cover_probe_mismatched_openbd_isbn');
    }
    const cover = summary?.cover;
    outcome.openbd_japanese_jacket = typeof cover === 'string' && cover.trim() ?
      (providerUrl(cover.trim(), [new URL(cover).hostname]) ? 'metadata_available' : 'invalid_url') :
      'not_available';
  } else {
    outcome.openbd_japanese_jacket = 'upstream_unavailable';
  }

  // One HEAD request checks whether an ISBN-specific Open Library fallback
  // actually exists. Its availability is independent of our app's correctness.
  try {
    const ol = await requestWithDeadline(request,
      'https://covers.openlibrary.org/b/isbn/' + knownOpenLibraryIsbn +
        '-M.jpg?default=false',
      { method: 'HEAD', timeoutMs: 8000 });
    outcome.openlibrary_known_jacket_http = ol.status;
    outcome.openlibrary_known_jacket = ol.status === 200 &&
      String(ol.headers.get('content-type')).startsWith('image/') ?
      'available' : 'unavailable';
  } catch {
    outcome.openlibrary_known_jacket = 'network_unavailable';
  }
  return outcome;
}

const invokedFile = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : '';
if (invokedFile === import.meta.url) {
  try {
    const result = await probeCoverStage(process.env.COVER_STAGE_BASE_URL || '');
    // Never log provider response bodies, returned URLs or credentials.
    console.log('cover_stage_probe ' + JSON.stringify(result));
  } catch (error) {
    const allowed = /^cover_probe_[a-z_]+$/;
    console.error(allowed.test(error?.message || '') ? error.message : 'cover_probe_network_error');
    process.exitCode = 1;
  }
}
