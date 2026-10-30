const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const account = readFileSync('lib/screens/account_settings_screen.dart', 'utf8');
const setup = readFileSync('lib/screens/profile_onboarding_screen.dart', 'utf8');
const service = readFileSync('lib/services/supabase_service.dart', 'utf8');
const sql = readFileSync(
  'supabase/migrations/20261030130100_restrict_privacy_password_recovery_to_oauth.sql', 'utf8',
);
const schema = readFileSync('supabase/schema.sql', 'utf8');

test('forgotten privacy password starts Google/X OAuth without post-frame dialog callback', () => {
  assert.match(account, /_PrivacyPasswordDialog\(\)/);
  assert.match(account, /if \(password\.isEmpty\) \{\s*await _startRecovery\(\)/);
  assert.match(account, /onPressed: \(\) => Navigator\.of\(context\)\.pop\(''\)/);
  assert.doesNotMatch(account, /widget\.onForgot\(\)/);
  assert.match(account, /beginPrivacyPasswordRecovery\(\)/);
  assert.match(account, /GoogleまたはXで本人確認してください/);
  assert.doesNotMatch(account, /登録メールアドレスに確認用リンクを送信/);
  assert.match(account, /連携サービスで本人確認/);
  assert.match(account, /currentOAuthProviderLabel/);
  assert.match(account, /Sharemariumが\$providerLabelのパスワードを入力・保存することはありません/);
  assert.match(service, /String\? get currentOAuthProvider/);
  assert.match(service, /String\? get currentOAuthProviderLabel/);
});

test('after OAuth return, use the exact first-time password setup layout', () => {
  assert.match(account, /PrivacyPasswordSetupScreen\(\s*isRecovery: true/);
  assert.doesNotMatch(account, /class _PrivacyPasswordRecoveryScreen/);
  assert.match(setup, /class PrivacyPasswordSetupScreen/);
  assert.match(setup, /this\.isRecovery = false/);
  assert.match(setup, /widget\.isRecovery\s*\?\s*'新しいパスワードを設定'/);
  assert.match(setup, /resetPrivacyPasswordAfterReauthentication\(/);
  assert.match(setup, /initializePrivacyPassword\(/);
  assert.match(setup, /新しいパスワード（確認）/);
  assert.match(setup, /Text\(widget\.isRecovery \? '再設定する' : '設定する'\)/);
  const main = readFileSync('lib/main.dart', 'utf8');
  assert.match(main, /openPrivacyPasswordRecovery:/);
  assert.match(main, /onPrivacyPasswordRecoveryCompleted:/);
  assert.match(main, /_openPrivacyPasswordRecovery = false/);
  assert.match(account, /widget\.onPrivacyPasswordRecoveryCompleted\?\.call\(\)/);
  assert.match(main, /privacy_password_recovery/);
});

test('recovery only supports currently enabled OAuth providers; never email OTP', () => {
  const beginning = service.slice(service.indexOf('Future<String?> beginPrivacyPasswordRecovery()'),
    service.indexOf('Future<String?> resetPrivacyPasswordAfterReauthentication('));
  assert.match(beginning, /currentUser\?\.appMetadata\['provider'\]/);
  assert.match(beginning, /'google', 'twitter', 'x'/);
  assert.match(beginning, /OAuthProvider\.google/);
  assert.match(beginning, /OAuthProvider\.x/);
  assert.match(beginning, /privacyRecovery: true/);
  assert.match(service, /privacy_password_recovery': '1'/);
  assert.doesNotMatch(beginning, /signInWithOtp|case 'email'|currentUser\?\.email/);
});

test('database rejects email and demands matching fresh OAuth after request', () => {
  for (const source of [sql, schema]) {
    assert.match(source, /current_provider NOT IN \('google', 'twitter', 'x'\)/);
    assert.match(source, /recovery\.provider NOT IN \('google', 'twitter', 'x'\)/);
    assert.match(source, /entry ->> 'method' = 'oauth'/);
    assert.doesNotMatch(
      source.slice(source.indexOf('CREATE OR REPLACE FUNCTION public.begin_privacy_password_recovery()'),
        source.indexOf('CREATE OR REPLACE FUNCTION public.change_privacy_password') < 0 ? undefined :
          source.indexOf('CREATE OR REPLACE FUNCTION public.change_privacy_password')),
      /current_provider NOT IN \('email'/,
    );
    assert.match(source, /entry ->> 'timestamp'/);
    assert.match(source, /recovery\.requested_at - interval '5 seconds'/);
    assert.match(source, /interval '15 minutes'/);
    assert.match(source, /WHERE profile_id = auth\.uid\(\)/);
    assert.match(source, /UPDATE public\.privacy_password_credentials/);
    assert.match(source, /password_hash = extensions\.crypt\(/);
    assert.match(source, /DELETE FROM public\.privacy_password_recovery_requests/);
  }
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.reset_privacy_password_after_reauthentication\(TEXT\) FROM PUBLIC/);
  assert.match(sql, /TO authenticated;/);
});
