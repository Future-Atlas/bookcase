const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const read = (file) => fs.readFileSync(path.join(__dirname, "../..", file), "utf8");

test("security migration enforces current viewer visibility for book counts", () => {
  const sql = read("supabase/migrations/20261102183000_harden_visible_engagement_sessions_avatars.sql");
  assert.match(sql, /public\.can_view_profile_content\(post\.profile_id\)/i);
  assert.match(sql, /public\.current_user_can_view_age_restricted\(\)/i);
  assert.match(sql, /public\.profile_can_expose_want_to_read\(wanted\.profile_id\)/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.check_session_ip_change\(inet,text\)/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.is_active_auth_session\(uuid,uuid\)\s+TO service_role/i);
  assert.match(sql, /FROM auth\.sessions AS s/i);
});

test("session guard verifies real JWT and session, ignores client-controlled IP headers", () => {
  const code = read("supabase/functions/session-guard/index.ts");
  assert.match(code, /admin\.auth\.getUser\(token\)/);
  assert.match(code, /signedSessionClaims\(token,\s*userId\)/);
  assert.match(code, /admin\.rpc\(\s*"is_active_auth_session"/);
  assert.match(code, /sessionActive:\s*true/);
  assert.match(code, /status.*401|reply\(request,.*401/);
  assert.doesNotMatch(code, /request\.headers\.get\(["']x-forwarded-for["']\)/i);
  assert.doesNotMatch(code, /request\.headers\.get\(["']x-real-ip["']\)/i);
  assert.doesNotMatch(code, /check_session_ip_change/);
});

test("Flutter signs out a revoked session instead of trusting IP change", () => {
  const code = read("lib/services/supabase_service.dart");
  assert.match(code, /if \(e\.status == 401\) return revokeCurrentSession\(\)/);
  assert.match(code, /if \(response\.status == 401\) return revokeCurrentSession\(\)/);
  assert.match(code, /checkedToken/);
  assert.doesNotMatch(code, /if \(data\['ipChanged'\] == true\)/);
});

test("all user avatar image widgets use the same strict URL allowlist", () => {
  const paths = [
    "lib/screens/user_profile_screen.dart",
    "lib/screens/account_settings_screen.dart",
    "lib/screens/follow_list_screen.dart",
    "lib/screens/post_engagement_users_screen.dart",
    "lib/screens/notifications_screen.dart",
    "lib/screens/book_list_screen.dart",
    "lib/widgets/post_card.dart",
  ];
  const policy = read("lib/services/avatar_url_policy.dart");
  assert.match(policy,/static String\? safeUrl/);
  assert.match(policy,/static ImageProvider\? image/);
  for (const file of paths) {
    const code=read(file);
    assert.match(code,/AvatarUrlPolicy\.image/);
    assert.doesNotMatch(code,/NetworkImage\(/);
  }
});
