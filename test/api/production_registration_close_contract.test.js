const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (p) => fs.readFileSync(path.join(__dirname,'../..',p),'utf8');

test('registration provides copy and paste for all text fields', () => {
  const source = read('lib/screens/profile_onboarding_screen.dart');
  for (const label of ['姓（Family name）', '名（Given name）',
                        '電話番号', 'ユーザー名', 'ユーザーID']) {
    assert.ok(source.includes(`_editableDecoration('${label}'`), label);
  }
  assert.match(source, /pasteClipboardInto\(controller\)/);
  assert.match(source, /copyFieldText\(controller\)/);
  assert.match(source, /'パスワードを貼り付け'/);
});
test('outside red book close circle retains theme-sensitive X', () => {
  const source = read('lib/widgets/book_detail_dialog_frame.dart');
  assert.match(source, /BorderSide\(color: Color\(0xFFD00303\), width: 2\)/);
  assert.match(source, /Brightness\.dark/);
  assert.match(source, /book-detail-close-button/);
  assert.match(source, /Navigator\.of\(context\)\.pop/);
});
