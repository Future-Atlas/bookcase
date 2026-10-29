import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const read = (path) =>
  readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8')

test('subscription UI remains disabled until legal terms are ready', () => {
  const flags = read('lib/config/feature_flags.dart')
  assert.match(
    flags,
    /static const bool subscriptionUiEnabled = false;/,
  )
})

test('favorites UI remains available while subscription UI is disabled', () => {
  const flags = read('lib/config/feature_flags.dart')
  const bookList = read('lib/screens/book_list_screen.dart')
  const profile = read('lib/screens/user_profile_screen.dart')
  const accountGate = read('lib/screens/account_suspension_gate.dart')

  assert.match(
    flags,
    /static const bool favoritesUiEnabled = true;/,
  )
  assert.match(bookList, /if \(FeatureFlags\.favoritesUiEnabled\)/)
  assert.match(
    bookList,
    /FeatureFlags\.favoritesUiEnabled &&\s+post\.profileId == currentProfileId/,
  )
  assert.match(profile, /FeatureFlags\.favoritesUiEnabled \? 1 : 0/)
  assert.match(profile, /FeatureFlags\.wantToReadUiEnabled \? 1 : 0/)
  assert.match(
    profile,
    /if \(FeatureFlags\.favoritesUiEnabled\)\s+_buildFavoritesTab\(\)/,
  )
  assert.match(
    accountGate,
    /FeatureFlags\.favoritesUiEnabled\s+\? FavoriteRetentionGate/,
  )
})

test('account settings hides the entire subscription section behind the release flag', () => {
  const settings = read('lib/screens/account_settings_screen.dart')
  const gate = settings.indexOf('if (FeatureFlags.subscriptionUiEnabled)')
  const section = settings.indexOf("const _SectionTitle('プラン・契約')")
  const screen = settings.indexOf('SubscriptionStatusScreen()')

  assert.ok(gate >= 0)
  assert.ok(section > gate)
  assert.ok(screen > gate)
})

test('locked feature messages do not advertise unreleased paid plans', () => {
  const paths = [
    'lib/screens/account_settings_screen.dart',
    'lib/screens/book_list_screen.dart',
    'lib/screens/user_profile_screen.dart',
    'lib/services/supabase_service.dart',
    'lib/services/reply_editing_service.dart',
    'lib/widgets/post_reply_actions.dart',
    'lib/widgets/favorite_retention_gate.dart',
  ]
  for (const path of paths) {
    assert.doesNotMatch(
      read(path),
      /Premium限定|Premium特典|サブスクでは|サブスク限定|契約終了後も|プラン変更により/,
      path,
    )
  }
  assert.match(read('lib/widgets/post_reply_actions.dart'), /ご自身の返信の削除/)
})

test('public legal documents describe only current free and permission-based access', () => {
  const paths = [
    'lib/screens/terms_screen.dart',
    'lib/screens/privacy_policy_screen.dart',
    'lib/screens/external_transmission_screen.dart',
  ]
  for (const path of paths) {
    assert.doesNotMatch(read(path), /サブスクリプション/, path)
  }
  assert.match(read(paths[0]), /有料プラン及び定期購入サービスは提供していません/)
})
