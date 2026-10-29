const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.join(__dirname, "../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("registration PII hardening migration reasserts RLS and least privilege", () => {
  const migration = read(
    "supabase/migrations/20261029100000_harden_private_account_data_access.sql",
  );
  for (const table of [
    "account_details",
    "legal_consents",
    "contact_requests",
    "privacy_password_credentials",
    "privacy_password_recovery_requests",
  ]) {
    assert.match(
      migration,
      new RegExp(`ALTER TABLE public\\.${table} ENABLE ROW LEVEL SECURITY`, "i"),
    );
  }
  assert.match(migration, /REVOKE ALL ON TABLE public\.account_details[\s\S]*FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT SELECT, INSERT, UPDATE ON TABLE public\.account_details[\s\S]*TO authenticated/i);
  assert.match(migration, /REVOKE ALL ON TABLE public\.privacy_password_credentials[\s\S]*FROM PUBLIC, anon, authenticated/i);
  assert.doesNotMatch(
    migration,
    /GRANT\s+SELECT(?:\s*,\s*[A-Z]+)*\s+ON\s+TABLE\s+public\.privacy_password_credentials/i,
  );
});

test("production database security audit is manual and read-only", () => {
  const workflow = read(".github/workflows/security-audit-production.yaml");
  const audit = read("scripts/audit-production-security.sql");

  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /\n\s*push:/);
  assert.match(workflow, /default_transaction_read_only=on/);
  assert.match(workflow, /scripts\/audit-production-security\.sql/);
  assert.doesNotMatch(workflow, /supabase db push|migration up|functions deploy/i);
  assert.match(audit, /begin read only;/i);
  assert.match(audit, /rollback;/i);
  assert.doesNotMatch(audit, /select\s+\*\s+from\s+public\.account_details/i);
  for (const table of [
    "account_details",
    "auth_session_ip_guards",
    "contact_requests",
    "favorites",
    "featured_books",
    "post_replies",
    "posts",
    "profiles",
    "session_ip_guards",
    "want_to_read_books",
  ]) {
    assert.match(audit, new RegExp(`'${table}'`), table);
  }
});

test("browser and public API source never references a Supabase secret key", () => {
  for (const file of [
    "web/index.html",
    "lib/main.dart",
    "lib/services/supabase_service.dart",
    "cloudflare/worker.mjs",
    "api/seo.js",
    "api/post-seo.js",
    "api/posts-seo.js",
    "api/sitemap.js",
  ]) {
    const source = read(file);
    assert.doesNotMatch(source, /SUPABASE_SERVICE_ROLE_KEY|sb_secret_/i, file);
  }
});

test("production responses enforce a CSP instead of report-only monitoring", () => {
  const worker = read("cloudflare/worker.mjs");
  const vercel = read("vercel.json");
  assert.match(worker, /headers\.set\("Content-Security-Policy", CSP_ENFORCED\)/);
  assert.doesNotMatch(worker, /Content-Security-Policy-Report-Only/);
  assert.match(worker, /script-src-attr 'none'/);
  assert.match(worker, /upgrade-insecure-requests/);
  assert.match(vercel, /"key": "Content-Security-Policy"/);
  assert.doesNotMatch(vercel, /Content-Security-Policy-Report-Only/);
});
