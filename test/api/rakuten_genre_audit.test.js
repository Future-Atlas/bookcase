const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { spawnSync } = require('node:child_process');

test('Rakuten genre audit script is valid JavaScript and never auto-blocks', () => {
  const result = spawnSync(process.execPath, ['--check', 'scripts/audit-rakuten-books-genres.mjs'], {
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  const source = readFileSync('scripts/audit-rakuten-books-genres.mjs', 'utf8');
  assert.match(source, /BooksGenre\/Search\/20121128/);
  assert.match(source, /requiresManualReview: true/);
  assert.match(source, /GENRE_AUDIT_MAX_NODES/);
  assert.doesNotMatch(source, /restrictedRakutenGenreIds\s*=/);
});

test('restrictions must use a verified registry, not a generic adult keyword guess', () => {
  const registry = readFileSync('lib/config/restricted_rakuten_genres.dart', 'utf8');
  const safety = readFileSync('lib/services/content_safety_service.dart', 'utf8');
  assert.match(registry, /verifiedAdultOnly/);
  assert.match(registry, /neverBlockBroadGenres/);
  assert.match(safety, /RestrictedRakutenGenres\.blockedIds/);
  assert.match(safety, /containsAdultContentTerms/);
});
