const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = (name) => fs.readFileSync(path.join(__dirname, '../../', name), 'utf8');

test('want-to-read remains hidden and favorites remain available', () => {
  const flags = read('lib/config/feature_flags.dart');
  const profile = read('lib/screens/user_profile_screen.dart');
  const cards = read('lib/widgets/post_card.dart');
  const books = read('lib/screens/book_list_screen.dart');
  assert.match(flags, /wantToReadUiEnabled = subscriptionUiEnabled/);
  assert.match(flags, /subscriptionUiEnabled = false/);
  assert.match(profile, /FeatureFlags.wantToReadUiEnabled \? 4 : 3/);
  assert.match(profile, /if \(FeatureFlags.wantToReadUiEnabled\) Tab\(text: '読みたい！'\)/);
  assert.match(profile, /_buildFavoritesTab\(\)/);
  assert.match(books, /if \(FeatureFlags.wantToReadUiEnabled\) Expanded/);
  assert.match(cards, /FeatureFlags.wantToReadUiEnabled/);
  assert.match(cards, /widget.favoriteLabel/);
});

test('rating ruler has 51 tick positions and labels every half point', () => {
  const slider = read('lib/widgets/star_rating_slider.dart');
  const composer = read('lib/widgets/post_composer_dialog.dart');
  assert.match(slider, /divisions: 50/);
  assert.match(slider, /tick <= 50/);
  assert.match(slider, /tick % 5 == 0/);
  assert.match(slider, /List.generate\(11/);
  assert.match(slider, /Icons.star/);
  assert.match(composer, /StarRatingSlider\(/);
  assert.match(composer, /hasSelectedRating = true/);
  assert.doesNotMatch(composer, /starValue = index \+ 1.0/);
});

test('both save paths allow tenths, and database permits zero', () => {
  const service = read('lib/services/supabase_service.dart');
  const sql = read('supabase/migrations/20261023160000_allow_zero_to_five_star_ratings.sql');
  assert.match(service, /_isValidPostRating\(rating\)/);
  assert.match(service, /rating >= 0/);
  assert.match(service, /rating <= 5/);
  assert.match(sql, /CHECK \(rating >= 0.0 AND rating <= 5.0\)/);
});
