const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const read = (file) =>
  fs.readFileSync(path.join(__dirname, "../..", file), "utf8");

test("legacy arbitrary-user read-count RPC is removed", () => {
  const migration = read(
    "supabase/migrations/20261021150000_remove_insecure_increment_read_count_rpc.sql",
  );
  assert.match(
    migration,
    /DROP FUNCTION IF EXISTS public\.increment_read_count\(UUID\)/i,
  );
  assert.doesNotMatch(read("supabase/schema.sql"), /FUNCTION "public"\."increment_read_count"/i);
});

test("contact requests are limited to five per rolling 24 hours", () => {
  const migration = read(
    "supabase/migrations/20261021151000_rate_limit_contact_requests.sql",
  );
  assert.match(migration, /recent_count >= 5/i);
  assert.match(migration, /interval '24 hours'/i);
  assert.match(migration, /pg_advisory_xact_lock/i);
  assert.match(migration, /SET search_path = ''/i);
  assert.match(migration, /NEW\.profile_id := requester/i);
  assert.match(migration, /CONTACT_RATE_LIMIT_EXCEEDED/i);
});

test("contact UI explains the 24-hour limit without exposing database details", () => {
  const service = read("lib/services/supabase_service.dart");
  const screen = read("lib/screens/contact_screen.dart");
  assert.match(service, /24時間以内に送信できるお問い合わせは5件までです/);
  assert.match(service, /24時間経過後にお送りください/);
  assert.match(screen, /運営チームが順次対応いたします/);
  assert.match(screen, /返信に時間がかかる場合があります/);
  assert.match(screen, /24時間以内に送信できるお問い合わせは5件までです/);
  assert.doesNotMatch(screen, /運勢チーム/);
  assert.match(service, /CONTACT_RATE_LIMIT_EXCEEDED/);
});

test("Vercel fallback keeps the same baseline browser security headers", () => {
  const config = JSON.parse(read("vercel.json"));
  const globalHeaders = config.headers.find((entry) => entry.source === "/(.*)");
  assert.ok(globalHeaders, "global fallback headers must exist");

  const headers = new Map(
    globalHeaders.headers.map(({ key, value }) => [key.toLowerCase(), value]),
  );
  assert.equal(headers.get("strict-transport-security"), "max-age=31536000");
  assert.equal(headers.get("x-frame-options"), "DENY");
  assert.equal(headers.get("x-content-type-options"), "nosniff");
  assert.equal(
    headers.get("referrer-policy"),
    "strict-origin-when-cross-origin",
  );
  assert.match(
    headers.get("content-security-policy") || "",
    /frame-ancestors 'none'/,
  );
  assert.match(
    headers.get("content-security-policy") || "",
    /script-src-attr 'none'/,
  );
  assert.match(
    headers.get("content-security-policy") || "",
    /upgrade-insecure-requests/,
  );
});

test("CodeQL scans supported source on protected branches and pull requests", () => {
  const workflow = read(".github/workflows/codeql.yaml");
  assert.match(workflow, /security-events:\s*write/);
  assert.match(workflow, /languages:\s*javascript-typescript/);
  assert.match(workflow, /github\/codeql-action\/init@v4/);
  assert.match(workflow, /github\/codeql-action\/analyze@v4/);
  assert.match(workflow, /\n\s+- main\s*\n\s+- develop/g);
});
