const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (relative) =>
  fs.readFileSync(path.join(__dirname, '../..', relative), 'utf8');

test('production two-factor enrollment and challenge support code paste', () => {
  const screen = read('lib/screens/totp_authentication_screen.dart');
  assert.equal((screen.match(/tooltip: '認証コードを貼り付け'/g) ?? []).length, 2);
  assert.equal((screen.match(/pasteClipboardInto\(_codeController\)/g) ?? []).length, 2);
  assert.match(screen, /maxLength: 6/);
  assert.match(screen, /verifyTotpCode/);
  assert.match(screen, /verifyTotpEnrollment/);
  assert.match(screen, /tooltip: 'パスワードを貼り付け'/);
});

test('privacy entry, change, and OAuth password recovery allow paste', () => {
  const settings = read('lib/screens/account_settings_screen.dart');
  const onboarding = read('lib/screens/profile_onboarding_screen.dart');
  for (const label of [
    'パスワードを貼り付け',
    '新しいパスワードを貼り付け',
    '新しいパスワードをコピー',
    '確認用パスワードを貼り付け',
    '確認用パスワードをコピー',
  ]) {
    assert.ok(settings.includes(label), label);
  }
  assert.match(onboarding, /'パスワードを貼り付け'/);
  assert.match(onboarding, /'パスワードをコピー'/);
  const clipboard = read('lib/utils/text_field_clipboard.dart');
  assert.match(clipboard, /Clipboard\.getData/);
  assert.match(clipboard, /Clipboard\.setData/);
});

test('mobile My bookshelf has exact 2:8:1:8:1:8:2 spacing', () => {
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
