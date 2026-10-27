const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "../..");
const html = fs.readFileSync(path.join(root, "web/index.html"), "utf8");
const tag = '<script id="sharemarium-legacy-hash-route">';
const start = html.indexOf(tag);
const end = html.indexOf("</script>", start);
assert.ok(start >= 0 && end > start, "legacy hash migration must run before Flutter starts");
const migrationCode = html.slice(start + tag.length, end);

function redirectLegacyUrl(href) {
  const location = new URL(href);
  let replacedUrl = null;
  let replacedState = null;
  const history = {
    state: { navigation: "original" },
    replaceState(state, _title, url) {
      replacedState = state;
      replacedUrl = new URL(url, location.origin).href;
    },
  };
  vm.runInNewContext(migrationCode, { window: { location, history }, URL, URLSearchParams });
  return { url: replacedUrl ?? href, wasReplaced: replacedUrl !== null, state: replacedState };
}

test("legacy hash paths become clean paths without a page reload", () => {
  for (const [oldUrl, pathPart] of [
    ["https://www.sharemarium.com/#/login", "/login"],
    ["https://www.sharemarium.com/#/book/9784101269313", "/book/9784101269313"],
    ["https://www.sharemarium.com/#/posts/11111111-1111-4111-8111-111111111111", "/posts/11111111-1111-4111-8111-111111111111"],
    ["https://www.sharemarium.com/#/users/example", "/users/example"],
    ["https://www.sharemarium.com/#/mypage", "/mypage"],
    ["https://www.sharemarium.com/#/", "/"],
  ]) {
    const result = redirectLegacyUrl(oldUrl);
    assert.equal(result.url, `https://www.sharemarium.com${pathPart}`);
    assert.equal(result.wasReplaced, true);
    assert.equal(result.state.navigation, "original");
  }
});

test("legacy route queries and existing tracking params survive the migration", () => {
  const result = redirectLegacyUrl(
    "https://www.sharemarium.com/?utm_source=shared#/settings?privacy_password_recovery=1",
  );
  const cleanUrl = new URL(result.url);
  assert.equal(cleanUrl.pathname, "/settings");
  assert.equal(cleanUrl.searchParams.get("utm_source"), "shared");
  assert.equal(cleanUrl.searchParams.get("privacy_password_recovery"), "1");
  assert.equal(cleanUrl.hash, "");
});

test("OAuth token fragments and clean URLs remain untouched", () => {
  for (const href of [
    "https://www.sharemarium.com/#access_token=secret&token_type=bearer",
    "https://www.sharemarium.com/?code=oauth-code&state=abc",
    "https://www.sharemarium.com/login",
    "https://www.sharemarium.com/book/9784101269313",
    "https://www.sharemarium.com/#//evil.example/",
    "https://www.sharemarium.com/book/9784101269313#/login",
  ]) {
    const result = redirectLegacyUrl(href);
    assert.equal(result.url, href);
    assert.equal(result.wasReplaced, false);
  }
});

test("legacy migration executes in the HTML head, before Flutter bootstraps", () => {
  const migrationPos = html.indexOf('<script id="sharemarium-legacy-hash-route">');
  assert.ok(migrationPos > html.indexOf('<base href="$FLUTTER_BASE_HREF" />'));
  assert.ok(migrationPos < html.indexOf("</head>"));
  const main = fs.readFileSync(path.join(root, "lib/main.dart"), "utf8");
  const pubspec = fs.readFileSync(path.join(root, "pubspec.yaml"), "utf8");
  assert.ok(main.includes("usePathUrlStrategy();"));
  assert.ok(pubspec.includes("flutter_web_plugins:"));
  assert.ok(pubspec.includes("sdk: flutter"));
});
