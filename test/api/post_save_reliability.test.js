const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = p => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8');

test('new review is committed once and not falsely marked failed by a second bookshelf write', () => {
  const src = read('lib/services/supabase_service.dart');
  const create = src.slice(src.indexOf('Future<bool> createPost({'), src.indexOf('Future<bool> deleteOwnPost('));
  const trigger = read('supabase/migrations/20260808090000_sync_bookshelf_with_posts.sql');
  assert.match(create, /\.from\('posts'\)\.insert\(/);
  assert.match(create, /notifyListeners\(\);\s*return true;/);
  assert.doesNotMatch(create, /await _upsertReadCollection\(/);
  assert.match(trigger, /AFTER INSERT OR DELETE ON public\.posts/);
  assert.match(trigger, /EXECUTE FUNCTION public\.sync_bookshelf_after_post_change\(\)/);
});

test('read shelf record without a review does not block the first post', () => {
  const src = read('lib/services/supabase_service.dart');
  const create = src.slice(src.indexOf('Future<bool> createPost({'), src.indexOf('Future<bool> deleteOwnPost('));
  assert.doesNotMatch(create, /isBookReadByCurrentUser/);
  assert.match(create, /\.from\('posts'\)\s*\.select\('id'\)/);
  assert.match(create, /すでに投稿済みです/);
});

test('post-save errors are actionable, sanitized and surfaced in the composer', () => {
  const service = read('lib/services/supabase_service.dart');
  const composer = read('lib/widgets/post_composer_dialog.dart');
  for (const code of ['23505', '23514', '42501', '42703', 'PGRST204']) {
    assert.match(service, new RegExp("'" + code + "'"));
  }
  assert.match(service, /String\? lastPostSaveError/);
  assert.match(service, /lastPostSaveError = _postSaveErrorFromException\(e\)/);
  assert.match(composer, /widget\.service\.lastPostSaveError \?\?/);
  assert.doesNotMatch(composer, /content: Text\(e\.toString\(\)\)/);
});
