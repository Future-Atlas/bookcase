const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

function read(file) {
  return fs.readFileSync(path.join(__dirname, '../..', file), 'utf8');
}

test('all book search surfaces request ten results with paging', () => {
  const repo = read('lib/repositories/book_repository.dart');
  const home = read('lib/controllers/book_list_controller.dart');
  const profile = read('lib/screens/profile_book_search_screen.dart');

  assert.match(repo, /String query, \{int page = 1, int count = 10\}/);
  assert.match(repo, /final slot = output\.length % 10/);
  assert.match(repo, /final preferred = slot < 4 \? 0 : \(slot < 7 \? 1 : 2\)/);
  assert.match(home, /count: 10,/);
  assert.match(profile, /searchBooksPage\(query, page: 1, count: 10\)/);
  assert.match(profile, /page: page, count: 10/);
  assert.match(profile, /さらに10件読み込む/);
});

test('want-to-read is usable without a subscription, but still respects profile privacy', () => {
  const migration = read('supabase/migrations/20261113013000_make_want_to_read_free.sql');
  const flags = read('lib/config/feature_flags.dart');
  const plan = read('lib/screens/subscription_status_screen.dart');

  assert.match(flags, /wantToReadUiEnabled = true/);
  assert.match(flags, /favoritesUiEnabled = false/);
  assert.match(migration, /public\.is_profile_active\(auth\.uid\(\)\)/);
  assert.match(migration, /public\.can_view_profile_content\(target_profile_id\)/);
  assert.match(migration, /CREATE POLICY "Visible want-to-read shelves can be read"/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.current_user_can_use_want_to_read\(\)/);
  assert.doesNotMatch(migration, /profile_has_active_subscription|profile_effective_subscription_plan/);
  assert.doesNotMatch(plan, /「読みたい！」・返信は利用不可|「読みたい！」を利用可能'[\s\S]*premium/);
});
