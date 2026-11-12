const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = (file) => fs.readFileSync(path.join(__dirname, '../../', file), 'utf8');

test('read and edit composer open a standalone keyboard-safe route', () => {
  const src = read('lib/widgets/post_composer_dialog.dart');
  assert.match(src, /Navigator\.of\(context\)\.push<bool>/);
  assert.match(src, /MaterialPageRoute<bool>/);
  assert.match(src, /resizeToAvoidBottomInset: true/);
  assert.match(src, /SingleChildScrollView\(/);
  assert.match(src, /scrollPadding: const EdgeInsets\.only\(bottom: 120\)/);
  assert.match(src, /maxLength: _postCommentMaxLength/);
  assert.doesNotMatch(src, /AlertDialog\(/);
});

test('temporary catalogue failures are not presented as zero results', () => {
  const repo = read('lib/repositories/book_repository.dart');
  const controller = read('lib/controllers/book_list_controller.dart');
  const screen = read('lib/screens/book_list_screen.dart');
  assert.match(repo, /if \(batch\.temporarilyUnavailable\)/);
  assert.match(repo, /throw const _CatalogTemporarilyUnavailable\(\)/);
  assert.match(repo, /temporarilyUnavailable: true/);
  assert.match(controller, /retrySearchBooks\(\)/);
  assert.match(controller, /searchTemporarilyUnavailable = true/);
  assert.match(screen, /検索を再試行/);
  assert.match(screen, /書籍データを取得できませんでした/);
  assert.match(screen, /results\.isEmpty && !_controller\.searchTemporarilyUnavailable/);
});
