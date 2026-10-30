const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const screen = readFileSync('lib/screens/account_settings_screen.dart', 'utf8');
const service = readFileSync('lib/services/supabase_service.dart', 'utf8');
const migration = readFileSync('supabase/migrations/20261030130000_allow_email_privacy_password_recovery.sql', 'utf8');
const schema = readFileSync('supabase/schema.sql', 'utf8');

test('forgot-privacy-password button signals parent directly and starts recovery', () => {
  assert.match(screen, /_PrivacyPasswordDialog\(\)/);
  assert.match(screen, /if \(password\.isEmpty\) \{\s*await _startRecovery\(\)/);
  assert.match(screen, /onPressed: \(\) => Navigator\.of\(context\)\.pop\(''\)/);
  assert.doesNotMatch(screen, /widget\.onForgot\(\)/);
  assert.match(screen, /beginPrivacyPasswordRecovery\(\)/);
  assert.match(screen, /メールから本人確認/);
});

test('email recovery cannot silently create users and uses the registered email', () => {
  const beginning = service.slice(service.indexOf('Future<String?> beginPrivacyPasswordRecovery()'),
    service.indexOf('Future<String?> resetPrivacyPasswordAfterReauthentication('));
  assert.match(beginning, /currentUser\?\.appMetadata\['provider'\]/);
  assert.match(beginning, /currentUser\?\.email\?\.trim\(\)/);
  assert.match(beginning, /case 'email':/);
  assert.match(beginning, /signInWithOtp\(/);
  assert.match(beginning, /shouldCreateUser: false/);
  assert.match(beginning, /emailRedirectTo: _privacyRecoveryRedirectUrl\(\)/);
  assert.match(beginning, /begin_privacy_password_recovery/);
});

test('social recovery uses same provider and returns to the privacy reset screen', () => {
  for (const provider of ['google', 'twitter', 'x', 'facebook', 'apple', 'discord']) {
    assert.match(service, new RegExp("case '" + provider + "':"));
  }
  assert.match(service, /privacyRecovery: true/);
  assert.match(service, /privacy_password_recovery': '1'/);
  const main = readFileSync('lib/main.dart', 'utf8');
  assert.match(main, /openPrivacyPasswordRecovery:/);
  assert.match(main, /privacy_password_recovery/);
});

test('database requires fresh email OTP or matching fresh OAuth after request', () => {
  for (const sql of [migration, schema]) {
    assert.match(sql, /current_provider NOT IN \('email', 'google'/);
    assert.match(sql, /email_confirmed_at IS NOT NULL/);
    assert.match(sql, /recovery\.provider = 'email' AND entry ->> 'method' IN \('otp', 'magiclink'\)/);
    assert.match(sql, /recovery\.provider <> 'email' AND entry ->> 'method' = 'oauth'/);
    assert.match(sql, /entry ->> 'timestamp'/);
    assert.match(sql, /recovery\.requested_at - interval '5 seconds'/);
    assert.match(sql, /interval '15 minutes'/);
    assert.match(sql, /WHERE profile_id = auth\.uid\(\)/);
    assert.match(sql, /UPDATE public\.privacy_password_credentials/);
    assert.match(sql, /password_hash = extensions\.crypt\(/);
    assert.match(sql, /DELETE FROM public\.privacy_password_recovery_requests/);
  }
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.reset_privacy_password_after_reauthentication\(TEXT\) FROM PUBLIC/);
  assert.match(migration, /TO authenticated;/);
  assert.doesNotMatch(migration, /'password'\s*\)/);
});
