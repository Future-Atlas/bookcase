const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '../..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('profile tabs divide the available width on mobile and desktop', () => {
  const profile = read('lib/screens/user_profile_screen.dart');
  const start = profile.indexOf('Widget _buildTabBar()');
  const end = profile.indexOf('Widget _buildPostsTab()', start);
  const tabBar = profile.slice(start, end);

  assert.match(tabBar, /width:\s*double\.infinity/);
  assert.match(tabBar, /isScrollable:\s*false/);
  assert.doesNotMatch(tabBar, /SizedBox\(width:\s*(56|74|94|100)/);
});

test('registration and settings collect only the supported optional gender values', () => {
  const onboarding = read('lib/screens/profile_onboarding_screen.dart');
  const settings = read('lib/screens/account_settings_screen.dart');
  const service = read('lib/services/supabase_service.dart');

  for (const source of [onboarding, settings]) {
    assert.match(source, /性別（任意）/);
    assert.match(source, /value:\s*'female'/);
    assert.match(source, /value:\s*'male'/);
    assert.match(source, /value:\s*'undisclosed'/);
  }
  assert.match(service, /'p_gender':\s*gender/);
  assert.match(service, /_allowedAccountGenders/);
});

test('gender migration is private, constrained, and backwards compatible', () => {
  const migration = read(
    'supabase/migrations/20261028140000_add_optional_account_gender.sql',
  );

  assert.match(migration, /ADD COLUMN IF NOT EXISTS gender TEXT NOT NULL DEFAULT 'undisclosed'/i);
  assert.match(migration, /UPDATE public\.account_details[\s\S]*SET gender = 'male'[\s\S]*WHERE gender = 'undisclosed'/i);
  assert.match(migration, /gender IN \('female', 'male', 'undisclosed'\)/i);
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.complete_registration/i);
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.update_private_account_details/i);
  assert.doesNotMatch(migration, /deleted_accounts[\s\S]{0,120}gender/i);
});

test('legal disclosures cover optional gender and the planned ad-model safeguards', () => {
  const policy = read('lib/screens/privacy_policy_screen.dart');
  const disclosure = read('lib/screens/external_transmission_screen.dart');

  assert.match(policy, /性別（任意。女性、男性又は無回答）/);
  assert.match(policy, /将来、読書・利用傾向と組み合わせた広告配信モデル/);
  assert.match(policy, /現時点では、年齢層又は性別を用いた個別広告選定を実施していません/);
  assert.match(policy, /18歳未満の利用者については、行動履歴、読書傾向又は性別を用いた個別広告選定を行いません/);
  assert.match(disclosure, /性別（任意。女性、男性又は無回答）/);
});
