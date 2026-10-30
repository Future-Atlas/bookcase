const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const read = (path) => fs.readFileSync(path, "utf8");

test("private account corrections are narrow and audited", () => {
  const migration = read(
    "supabase/migrations/20261029143000_add_audited_private_data_controls.sql",
  );

  assert.match(migration, /REVOKE UPDATE ON TABLE public\.account_details FROM authenticated/);
  assert.match(migration, /update_own_private_contact_details/);
  assert.match(migration, /admin_read_private_account_details/);
  assert.match(migration, /admin_update_private_account_details/);
  assert.match(migration, /private_data_admin_audit_immutable/);
  assert.match(migration, /changed_fields TEXT\[\]/);
  assert.doesNotMatch(
    migration.match(/CREATE TABLE IF NOT EXISTS public\.private_data_admin_audit[\s\S]*?\);/)?.[0] ?? "",
    /family_name|given_name|birth_date|phone_number|gender|email/,
  );
});

test("the account UI keeps immutable identity fields read-only", () => {
  const settings = read("lib/screens/account_settings_screen.dart");
  const adminPanel = read("lib/widgets/private_account_admin_panel.dart");

  assert.match(settings, /labelText: '姓（Family name）',[\s\S]*?readOnly: true|readOnly: true,[\s\S]*?labelText: '姓（Family name）'/);
  assert.match(settings, /labelText: '名（Given name）'/);
  assert.match(settings, /電話番号・性別を保存する/);
  assert.match(adminPanel, /問い合わせ・事件・受付番号/);
  assert.match(adminPanel, /管理者追加パスワード/);
  assert.match(adminPanel, /メールアドレス（変更不可）/);
});

test("legal versions disclose the audited correction process", () => {
  const versions = read("lib/services/legal_document_versions.dart");
  const privacy = read("lib/screens/privacy_policy_screen.dart");

  assert.match(versions, /static const terms = '1\.15\.0'/);
  assert.match(versions, /static const privacy = '1\.14\.0'/);
  assert.match(privacy, /追加パスワード/);
  assert.match(privacy, /監査記録には、個人情報の値そのものを重複して保存しません/);
});
