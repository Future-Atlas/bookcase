const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = (file) => fs.readFileSync(path.join(__dirname, '../..', file), 'utf8');

test('production Rakuten API errors propagate rather than masquerade as no matches', () => {
  const api = read('lib/api/rakuten_api.dart');
  assert.match(api, /bool throwOnSearchFailure = false/);
  assert.match(api, /if \(throwOnSearchFailure\) rethrow/);
  assert.match(api, /throwOnSearchFailure: true,/);
  assert.match(api, /throw StateError\('Rakuten catalog request unavailable'\)/);
});

test('search continues with NDL when production Rakuten returns no usable books', () => {
  const repo = read('lib/repositories/book_repository.dart');
  assert.match(repo, /else if \(!cursor\.hasMoreUpstream\)/);
  assert.match(repo, /Only the first page may choose NDL/);
  assert.match(repo, /_ndlFallbackQuery = clean/);
  assert.match(repo, /final batch = rakutenKeywordPageFetcher != null/);
  assert.match(repo, /cursor\.ready\.isNotEmpty \|\| cursor\.hasMoreUpstream/);
  assert.match(repo, /final firstQuota = \(count \* 0\.4\)\.round\(\)/);
  assert.match(repo, /temporarilyUnavailable: true/);
});
