// Read-only audit of the official Rakuten Books genre taxonomy.
// Requires RAKUTEN_APP_ID and RAKUTEN_ACCESS_KEY in the environment.
// Does NOT block genres or change any customer data.
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const appId = process.env.RAKUTEN_APP_ID;
const accessKey = process.env.RAKUTEN_ACCESS_KEY;
const output = process.env.GENRE_AUDIT_OUTPUT || 'rakuten-genre-audit.json';
const root = process.env.GENRE_AUDIT_ROOT || '001';
const maxNodes = Number(process.env.GENRE_AUDIT_MAX_NODES || 300);
const delayMs = Number(process.env.GENRE_AUDIT_DELAY_MS || 400);
const validId = /^\d{3}(?:\d{3})*$/;
const candidateName = /成人|成年|アダルト|18禁|18歳以上|R[\s-]?18|ポルノ|エロティック|adult|porn|erotic|age.restricted/i;

if (!appId || !accessKey) {
  throw new Error('Missing RAKUTEN_APP_ID or RAKUTEN_ACCESS_KEY (values are never printed).');
}
if (!validId.test(root) || !Number.isInteger(maxNodes) || maxNodes < 1 || maxNodes > 2000 ||
    !Number.isInteger(delayMs) || delayMs < 250 || delayMs > 10000) {
  throw new Error('Invalid GENRE_AUDIT_ROOT, GENRE_AUDIT_MAX_NODES or GENRE_AUDIT_DELAY_MS.');
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const asObject = (value) => value && typeof value === 'object' ? value : null;
const unwrap = (obj) => {
  const value = asObject(obj);
  return asObject(value?.child) || asObject(value?.current) || asObject(value?.parent) || value;
};
const normalizedChildren = (raw) => {
  const value = asObject(raw);
  const direct = value?.children || value?.Children || [];
  const collection = Array.isArray(direct)
    ? direct : (Array.isArray(direct.child) ? direct.child : (direct.child ? [direct.child] : []));
  return collection.map(unwrap).filter(Boolean);
};

async function genreLookup(id) {
  const url = new URL('https://openapi.rakuten.co.jp/services/api/BooksGenre/Search/20121128');
  url.searchParams.set('format', 'json');
  url.searchParams.set('applicationId', appId);
  url.searchParams.set('accessKey', accessKey);
  url.searchParams.set('booksGenreId', id);
  for (let attempt = 0; attempt < 4; attempt++) {
    const response = await fetch(url, { headers: { 'Accept': 'application/json' }, signal: AbortSignal.timeout(20000) });
    if (response.status === 429 || response.status === 503) {
      if (attempt === 3) throw new Error('Rakuten genre API rate limit/availability error: HTTP ' + response.status);
      await wait((attempt + 1) * 2000);
      continue;
    }
    if (!response.ok) throw new Error('Rakuten genre API returned HTTP ' + response.status + ' for genre ' + id);
    return await response.json();
  }
}

const seen = new Set();
const pending = [{ id: root, path: [] }];
const scanned = [];
let stopped = false;

while (pending.length && scanned.length < maxNodes) {
  const entry = pending.shift();
  if (seen.has(entry.id)) continue;
  seen.add(entry.id);
  const raw = await genreLookup(entry.id);
  const current = unwrap(raw.current || raw.Current || {});
  const id = String(current?.booksGenreId || entry.id);
  const name = String(current?.booksGenreName || '');
  const path = [...entry.path, name || id];
  if (!validId.test(id)) throw new Error('Unexpected Rakuten genre ID in response.');
  scanned.push({ id, name, path, candidate: candidateName.test(name), requiresManualReview: true });
  for (const child of normalizedChildren(raw)) {
    const nextId = String(child.booksGenreId || '');
    if (validId.test(nextId) && !seen.has(nextId)) pending.push({ id: nextId, path });
  }
  await wait(delayMs);
}
if (pending.length) stopped = true;

const result = {
  source: 'Rakuten BooksGenre/Search/20121128',
  root,
  checkedAt: new Date().toISOString(),
  checkedCount: scanned.length,
  incomplete: stopped,
  candidateCount: scanned.filter((item) => item.candidate).length,
  candidates: scanned.filter((item) => item.candidate),
  genres: scanned,
  warning: 'Names are suggestions for manual verification only. Never auto-block an ID based on its text alone. The Rakuten adult-site classification may be separate from genre IDs.'
};
await mkdir(dirname(output), { recursive: true });
await writeFile(output, JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
console.log('Rakuten genre audit saved (' + scanned.length + ' inspected, ' + result.candidateCount + ' name candidates, incomplete=' + stopped + ').');
console.log('Review artifact ' + output + '. No IDs have been automatically blocked.');
