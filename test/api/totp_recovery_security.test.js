const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const migration = readFileSync(
  'supabase/migrations/20261031100000_add_totp_recovery_controls.sql',
  'utf8',
);
const edge = readFileSync('supabase/functions/totp-recovery/index.ts', 'utf8');
const service = readFileSync('lib/services/supabase_service.dart', 'utf8');
const enrollment = readFileSync(
  'lib/screens/totp_authentication_screen.dart',
  'utf8',
);
const onboarding = readFileSync(
  'lib/screens/profile_onboarding_screen.dart',
  'utf8',
);
const account = readFileSync('lib/screens/account_settings_screen.dart', 'utf8');
const contact = readFileSync('lib/screens/contact_screen.dart', 'utf8');
const admin = readFileSync('lib/widgets/private_account_admin_panel.dart', 'utf8');
const config = readFileSync('supabase/config.toml', 'utf8');
const workflow = readFileSync('.github/workflows/supabase-deploy.yaml', 'utf8');

test('new and existing accounts must enroll and verify TOTP before the app opens', () => {
  assert.match(onboarding, /_OnboardingRequirement\.totpEnrollment/);
  assert.match(onboarding, /_OnboardingRequirement\.totpChallenge/);
  assert.match(onboarding, /hasVerifiedTotpFactor\(\)/);
  assert.match(onboarding, /requiresTotpChallenge\(\)/);
  assert.match(enrollment, /QrImageView\(/);
  assert.match(enrollment, /認証アプリの6桁コード/);
  assert.match(service, /auth\.mfa\.enroll\(/);
  assert.match(service, /issuer: 'Sharemarium'/);
});

test('privacy password recovery requires fresh OAuth and a protected TOTP verification', () => {
  assert.match(account, /purpose: 'privacy_recovery'/);
  assert.doesNotMatch(onboarding, /recoveryTotpChallenge/);
  assert.match(account, /isPrivacyRecoveryTotpVerified/);
  assert.match(edge, /validate_privacy_password_recovery_oauth/);
  assert.match(edge, /record_totp_verification_success/);
  assert.match(migration, /totp_verified_at/);
  assert.match(
    migration,
    /AND totp_verified_at >= timezone\('utc'::text, now\(\)\) - interval '15 minutes'/,
  );
  assert.match(migration, /Fresh OAuth authentication required/);
});

test('five invalid recovery codes create a 24-hour server-side lock', () => {
  assert.match(migration, /failed_attempts SMALLINT NOT NULL DEFAULT 0/);
  assert.match(migration, /least\(5, row_value\.failed_attempts \+ 1\)/);
  assert.match(migration, /interval '24 hours'/);
  assert.match(edge, /record_totp_verification_failure/);
  assert.match(edge, /status = failedState\.locked === true \? 429 : 400/);
  assert.match(enrollment, /あと\$\{state\?\.remainingAttempts \?\? 5\}回で、24時間ロックされます/);
  assert.match(enrollment, /formatJapaneseMonthDayTime\(retryAt\)/);
  assert.match(enrollment, /（24時間後）以降に再度入力してください/);
  assert.match(enrollment, /ロック中も他の画面は閲覧できます/);
  assert.match(enrollment, /enabled: !locked && _factorId != null/);
  assert.match(edge, /if \(purpose === 'login'\)/);
  assert.doesNotMatch(migration, /TOTP verification is temporarily locked/);
});

test('self and administrator TOTP resets are authorized and append-only audited', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.totp_recovery_audit/);
  assert.match(migration, /action IN \('self_reenroll', 'admin_reset'\)/);
  assert.match(
    migration,
    /outcome IN \('authorized', 'completed', 'failed'\)/,
  );
  assert.match(migration, /totp_recovery_audit_immutable/);
  assert.match(migration, /authorize_self_totp_reenrollment/);
  assert.match(migration, /authorize_admin_totp_reset/);
  assert.match(edge, /admin\.auth\.admin\.mfa\.deleteFactor/);
  assert.match(edge, /totp_recovery_audit/);
  assert.match(edge, /outcome: 'authorized'/);
  assert.match(edge, /outcome: deletionError \? 'failed' : 'completed'/);
  assert.doesNotMatch(edge, /totp_recovery_audit[\s\S]{0,200}(secret|code):/i);
  assert.match(migration, /AAL2 authentication required/);
  assert.match(admin, /監査記録を残して認証アプリを解除/);
  assert.match(contact, /'totp_recovery': '認証用QRコードの再取得'/);
});

test('the guarded function is explicit in validation and deployment lists', () => {
  assert.match(config, /\[functions\.totp-recovery\]\s+verify_jwt = true/);
  assert.match(workflow, /admin-delete-account\s+totp-recovery\s+billing-checkout/);
});
