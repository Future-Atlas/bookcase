const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.join(__dirname, "../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

function responseRecorder() {
  return {
    headers: {},
    statusCode: 200,
    body: "",
    setHeader(name, value) { this.headers[name] = value; },
    status(code) { this.statusCode = code; return this; },
    send(value) { this.body = String(value); return this; },
  };
}

test("terms already explain advertisements, sponsored reviews and third-party transactions", () => {
  const terms = read("lib/screens/terms_screen.dart");
  assert.match(terms, /第23条（広告及び外部サイト）/);
  assert.match(terms, /広告配信事業者その他の外部事業者へ送信される情報/);
  assert.match(terms, /「広告」「PR」「献本」「提供」/);
});

test("privacy policy identifies active Ninja AdMax and conditional Google ads", () => {
  const policy = read("lib/screens/privacy_policy_screen.dart");
  assert.match(policy, /忍者ツールズ株式会社/);
  assert.match(policy, /忍者AdMax/);
  assert.match(policy, /IPアドレス、閲覧ページのURL/);
  assert.match(policy, /https:\/\/corp\.ninja\.co\.jp\/privacy\/cookie\//);
  assert.match(policy, /Googleによる広告配信（Google AdSense）は、現在の広告配信には使用していません/);
  assert.match(policy, /https:\/\/adssettings\.google\.com\//);
  assert.match(policy, /2026年10月12日／バージョン1\.11\.0/);
  assert.match(policy, /\*\*最終改定日\*\*\s*2026年10月12日/);
});

test("external-transmission disclosure names the actual advertising recipient", () => {
  const disclosure = read("lib/screens/external_transmission_screen.dart");
  assert.match(disclosure, /忍者ツールズ株式会社（忍者AdMax）/);
  assert.match(disclosure, /忍者AdMaxの広告を掲載します/);
  assert.match(disclosure, /IPアドレス、通信に関するリクエスト情報/);
  assert.match(disclosure, /認証トークン又はレビュー本文/);
  assert.match(disclosure, /https:\/\/corp\.ninja\.co\.jp\/privacy\/tieup\//);
  assert.match(disclosure, /Google AdSenseによる広告配信は、現在の本サービスでは稼働していません/);
  assert.match(disclosure, /2026年10月12日／バージョン1\.10\.0/);
});

test("legal versions are independent and trigger re-confirmation for signed-in users", () => {
  const versions = read("lib/services/legal_document_versions.dart");
  assert.match(versions, /bundle = '1\.14\.0'/);
  assert.match(versions, /terms = '1\.11\.0'/);
  assert.match(versions, /privacy = '1\.11\.0'/);
  assert.match(versions, /externalTransmission = '1\.10\.0'/);
});

test("legal revision history agrees with current document versions", () => {
  const doc = read("docs/legal_changelog.md");
  assert.match(doc, /プライバシーポリシー \| 1\.11\.0/);
  assert.match(doc, /外部送信に関する公表事項 \| 1\.10\.0/);
  assert.match(doc, /2026年10月12日 \| 1\.11\.0/);
});

test("SEO legal rendering inherits disclosure without injecting ad scripts", async () => {
  delete require.cache[require.resolve("../../api/legal-seo")];
  const handler = require("../../api/legal-seo");
  for (const [route, marker] of [
    ["privacy", "忍者AdMax"],
    ["external-transmission", "忍者ツールズ株式会社"],
  ]) {
    const res = responseRecorder();
    await handler({query: {path: route}}, res);
    assert.equal(res.statusCode, 200);
    assert.match(res.body, new RegExp(marker));
    assert.doesNotMatch(res.body, /<script\b/i);
    assert.doesNotMatch(res.body, /pagead2\.googlesyndication\.com/);
  }
});
