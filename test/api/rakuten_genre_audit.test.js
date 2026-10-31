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

test('minor filtering covers direct details, featured books and profile shelves', () => {
  const home = readFileSync('lib/screens/book_list_screen.dart', 'utf8');
  const controller = readFileSync('lib/controllers/book_list_controller.dart', 'utf8');
  const profile = readFileSync('lib/screens/user_profile_screen.dart', 'utf8');
  const service = readFileSync('lib/services/supabase_service.dart', 'utf8');

  assert.match(home, /ContentSafetyService\.isAdultBook\(book\)[\s\S]*canViewAdultContent\(\)/);
  assert.match(home, /openedFromDirectUrl[\s\S]*_replaceBrowserPath\('\/'\)/);
  assert.match(controller, /featuredBooks[\s\S]*ContentSafetyService\.isAdultBook\(book\)/);
  assert.match(profile, /_showSearchedBookDetailDialog[\s\S]*ContentSafetyService\.isAdultBook\(book\)/);
  assert.match(service, /fetchUserWantToRead[\s\S]*ContentSafetyService\.isAdultBook\(book\)/);
  assert.match(service, /_resolveBooksByIds[\s\S]*ContentSafetyService\.isAdultBook\(book\)/);
});
