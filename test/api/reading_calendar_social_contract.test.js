const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (p) => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8');

test('calendar access is follower-only and owner exclusions are enforced in database', () => {
  const sql = read('supabase/migrations/20261111180000_share_reading_calendar_with_followers.sql');
  assert.match(sql, /CREATE OR REPLACE FUNCTION public.can_view_reading_calendar\(target_owner uuid\)/);
  assert.match(sql, /follow.status = 'accepted'/);
  assert.match(sql, /reading_calendar_hidden_followers AS hidden/);
  assert.match(sql, /public.is_blocked_between/);
  assert.match(sql, /ended_at IS NOT NULL/);
  assert.match(sql, /DROP POLICY IF EXISTS "Readers can see only their own reading sessions"/);
  assert.match(sql, /REVOKE ALL ON public.reading_calendar_hidden_followers FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /CREATE POLICY "Owner can read calendar exclusions"/);
});

test('owner controls hidden followers only via authenticated server-side RPC', () => {
  const sql = read('supabase/migrations/20261111180000_share_reading_calendar_with_followers.sql');
  const settings = read('lib/screens/reading_calendar_visibility_screen.dart');
  assert.match(sql, /CREATE OR REPLACE FUNCTION public.set_reading_calendar_follower_hidden/);
  assert.match(sql, /requester := auth.uid\(\)/);
  assert.match(sql, /follow.following_id = requester/);
  assert.match(sql, /follow.status = 'accepted'/);
  assert.match(sql, /DELETE FROM public.notifications[\s\S]*type = 'reading_session'/);
  assert.match(settings, /読書カレンダーを表示しない人/);
  assert.match(settings, /_readingService.setFollowerHidden/);
});

test('finished sessions notify eligible followers, not hidden followers', () => {
  const sql = read('supabase/migrations/20261111180000_share_reading_calendar_with_followers.sql');
  assert.match(sql, /CREATE TRIGGER reading_sessions_create_follower_notification/);
  assert.match(sql, /AFTER UPDATE OF ended_at/);
  assert.match(sql, /NOT EXISTS \([\s\S]*reading_calendar_hidden_followers AS hidden/);
  assert.match(sql, /type = 'reading_session'/);
  assert.match(sql, /CREATE POLICY "Users read only eligible notifications"/);
  assert.match(sql, /public.can_view_reading_calendar\(session.profile_id\)/);
});

test('reader reactions support the exact post reaction types and are scoped', () => {
  const sql = read('supabase/migrations/20261111180000_share_reading_calendar_with_followers.sql');
  const service = read('lib/services/reading_session_service.dart');
  const calendar = read('lib/screens/reading_calendar_tab.dart');
  assert.match(sql, /reaction_type IN \('like','love','sad'\)/);
  assert.match(sql, /session.profile_id <> auth.uid\(\)/);
  assert.match(service, /PostReactionType.fromDatabase/);
  assert.match(service, /toggleReaction\(/);
  assert.match(calendar, /PostReactionType.values/);
  assert.match(calendar, /_reactionButtons\(session/);
});
