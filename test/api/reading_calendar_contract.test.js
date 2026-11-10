const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const read = (file) => fs.readFileSync(path.join(__dirname, "../..", file), "utf8");

test("reading history is read-only for clients and belongs only to its owner", () => {
  const migration = read("supabase/migrations/20261110190000_create_reading_sessions.sql");
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/i);
  assert.match(migration, /REVOKE ALL ON TABLE public\.reading_sessions FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT SELECT ON TABLE public\.reading_sessions TO authenticated/i);
  assert.match(migration, /profile_id = auth\.uid\(\)/i);
  assert.doesNotMatch(migration, /GRANT (?:INSERT|UPDATE|DELETE) ON TABLE public\.reading_sessions TO authenticated/i);
});

test("reading timer timestamps and cap are enforced in authenticated RPCs", () => {
  const migration = read("supabase/migrations/20261110190000_create_reading_sessions.sql");
  assert.match(migration, /DEFAULT clock_timestamp\(\)/i);
  assert.match(migration, /reading_sessions_one_active_per_user_idx/);
  assert.match(migration, /RETURNS uuid[\s\S]*SECURITY DEFINER SET search_path = ''/i);
  assert.match(migration, /least\(clock_timestamp\(\), started_at \+ interval '24 hours'\)/i);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.finish_reading_session/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.start_reading_session\(text,text,text\)/);
});

test("registration clipboard and calendar stay separate from normal posting", () => {
  const onboarding = read("lib/screens/profile_onboarding_screen.dart");
  const profile = read("lib/screens/user_profile_screen.dart");
  const search = read("lib/screens/profile_book_search_screen.dart");
  const frame = read("lib/widgets/book_detail_dialog_frame.dart");

  assert.match(onboarding, /'パスワードを貼り付け'/);
  assert.match(onboarding, /Clipboard\.getData\('text\/plain'\)/);
  assert.match(onboarding, /'パスワードをコピー'/);
  assert.match(profile, /Tab\(text: 'カレンダー'\)/);
  assert.match(profile, /'カレンダーに追加'/);
  assert.match(search, /calendarSelection/);
  assert.match(frame, /BorderSide\(color: Color\(0xFFD00303\), width: 2\)/);
});
