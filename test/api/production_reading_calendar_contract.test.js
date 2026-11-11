const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = (name) => fs.readFileSync(path.join(__dirname, '../..', name), 'utf8');

test('production My Page exposes private calendar between bookshelf and favorites', () => {
  const source = read('lib/screens/user_profile_screen.dart');
  assert.match(source, /const Tab\(text: 'My 本棚'\),\s+const Tab\(text: 'カレンダー'\)/);
  assert.match(source, /ReadingCalendarTab\(/);
  assert.match(source, /ownerId: _profile!\.id/);
  assert.match(source, /onResume: _isOwnProfile \? _resumeCalendarTimer : null/);
  assert.match(source, /tooltip: calendarSelected \? 'カレンダーに追加'/);
  assert.match(source, /ReadingTimerScreen\(/);
});

test('calendar book picker returns selected book without posting a review', () => {
  const source = read('lib/screens/profile_book_search_screen.dart');
  assert.match(source, /calendarSelection = false/);
  assert.match(source, /if \(widget\.calendarSelection\)\s+FilledButton\.icon\(/);
  assert.match(source, /Navigator\.of\(context\)\.pop\(book\)/);
  assert.match(source, /if \(!widget\.calendarSelection\)\s+FutureBuilder<bool>/);
});

test('reading sessions stay server-timed and user-scoped', () => {
  const migration = read('supabase/migrations/20261110190000_create_reading_sessions.sql');
  const service = read('lib/services/reading_session_service.dart');
  assert.match(migration, /profile_id = auth\.uid\(\)/);
  assert.match(migration, /interval '24 hours'/);
  assert.match(migration, /start_reading_session/);
  assert.match(service, /'start_reading_session'/);
  assert.match(service, /'finish_reading_session'/);
  assert.doesNotMatch(service, /'started_at':/);
});

test('circular calendar covers preserve entire jacket artwork', () => {
  const cover = read('lib/widgets/reading_cover_art.dart');
  assert.match(cover, /BoxFit\.contain/);
  assert.match(cover, /parsed\.scheme == 'https'/);
});
