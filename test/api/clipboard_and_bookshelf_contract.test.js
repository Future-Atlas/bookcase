const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (relative) => fs.readFileSync(
  path.join(__dirname, '../..', relative), 'utf8'
);

test('privacy and reset passwords provide copy or paste explicitly', () => {
  const settings = read('lib/screens/account_settings_screen.dart');
  const onboarding = read('lib/screens/profile_onboarding_screen.dart');
  assert.match(settings, /'パスワードを貼り付け'/);
  assert.match(settings, /'新しいパスワードを貼り付け'/);
  assert.match(settings, /'新しいパスワードをコピー'/);
  assert.match(settings, /'確認用パスワードを貼り付け'/);
  assert.match(settings, /'確認用パスワードをコピー'/);
  assert.match(onboarding, /'パスワードを貼り付け'/);
  assert.match(onboarding, /'パスワードをコピー'/);
  const clipboard = read('lib/utils/text_field_clipboard.dart');
  assert.match(clipboard, /Clipboard\.getData/);
  assert.match(clipboard, /Clipboard\.setData/);
});

test('MFA pastes six digit code without modifying verification requirements', () => {
  const source = read('lib/screens/mfa_settings_screen.dart');
  assert.match(source, /'認証コードを貼り付け'/);
  assert.match(source, /pasteClipboardInto\(_codeController\)/);
  assert.match(source, /maxLength: 6/);
  assert.match(source, /RegExp\(r'\^\[0-9\]\{6\}\$'\)/);
});

test('mobile My bookshelf applies proportional spacing without internal card margins', () => {
  const shelf = read('lib/screens/user_profile_screen.dart');
  const card = read('lib/widgets/book_card.dart');
  const geometry = read('lib/utils/mobile_bookshelf_geometry.dart');
  assert.match(shelf, /MobileBookshelfGeometry\(constraints\.maxWidth\)/);
  assert.match(shelf, /mobile \? geometry\.interBookGap : 12/);
  assert.match(shelf, /marginRight: mobile \? 0 : 16/);
  assert.match(shelf, /marginBottom: mobile \? 0 : 12/);
  assert.match(card, /bottom: widget\.marginBottom/);
  assert.match(geometry, /double get outerPadding => 2 \* unit/);
  assert.match(geometry, /double get interBookGap => unit/);
  assert.match(geometry, /double get bookWidth => 8 \* unit/);
});
