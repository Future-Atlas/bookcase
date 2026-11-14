const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = (file) => fs.readFileSync(path.join(__dirname, '../..', file), 'utf8');
const migration = read('supabase/migrations/20261114143000_unify_want_to_read_book_state.sql');

test('both book and post taps use one unique user-book shelf relationship', () => {
  assert.match(migration, /IF EXISTS \([\s\S]*?FROM public\.want_to_read_books[\s\S]*?book_id = target_book_id/);
  assert.match(migration, /DELETE FROM public\.want_to_read_books[\s\S]*?book_id = target_book_id/);
  assert.match(migration, /INSERT INTO public\.want_to_read_books/);
  assert.match(migration, /source_post_id IS NOT NULL THEN[\s\S]*?INSERT INTO public\.post_want_to_reads/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.doesNotMatch(migration, /has_other_post_source|existing_direct/);
});

test('post displays and book counts use one RLS-protected book source', () => {
  const service = read('lib/services/supabase_service.dart');
  const postCard = read('lib/widgets/post_card.dart');
  const label = read('lib/widgets/book_action_label.dart');
  const detail = read('lib/widgets/book_detail_dialog.dart');
  assert.match(read('supabase/migrations/20260902090000_add_want_to_read_feature.sql'),
    /PRIMARY KEY \(profile_id, book_id\)/);
  assert.match(migration, /count\(DISTINCT wanted\.profile_id\)/);
  assert.match(migration, /SECURITY INVOKER/);
  assert.match(service, /get_book_want_to_read_states/);
  assert.match(service, /wantToReadStateFor\(String bookId\)/);
  assert.match(postCard, /wantToReadStateFor\(post\.bookId\)/);
  assert.match(label, /wantToReadStateFor\(bookId\)/);
  assert.match(detail, /wantToReadStateFor\(book\.id\)/);
  assert.doesNotMatch(service, /\.from\('post_want_to_reads'\)/);
  assert.match(service, /\.from\('want_to_read_books'\)[\s\S]*?\.select\('profile_id, created_at'\)/);
});

test('own posts, hidden posts and read books remain protected', () => {
  assert.match(migration, /target_post\.profile_id = actor/);
  assert.match(migration, /current_user_can_view_age_restricted\(\)/);
  assert.match(migration, /public\.can_view_profile_content\(target_post\.profile_id\)/);
  assert.match(migration, /already_read/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.toggle_want_to_read[\s\S]*?FROM PUBLIC, anon/);
});
