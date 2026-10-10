const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const read = (file) => fs.readFileSync(path.join(__dirname, "../..", file), "utf8");

test("timeline contains at most one ad after three real posts", () => {
  const source = read("lib/screens/book_list_screen.dart");
  const start = source.indexOf("Widget _buildTimeline()");
  const end = source.indexOf("Widget _buildFooter()", start);
  const timeline = source.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.match(timeline, /_controller\.timelinePosts\.length >= 3/);
  assert.match(timeline, /if \(hasAdSlot && index == 3\)/);
  assert.match(timeline, /return const TimelineAdSlot\(\)/);
  assert.match(timeline, /final postIndex = hasAdSlot && index > 3 \? index - 1 : index/);
  assert.equal((timeline.match(/TimelineAdSlot\(/g) || []).length, 1);
});

test("ads are only supported on Flutter Web and disabled until configured", () => {
  const platform = read("lib/widgets/timeline_ad_slot.dart");
  const stub = read("lib/widgets/timeline_ad_slot_stub.dart");
  const web = read("lib/widgets/timeline_ad_slot_web.dart");
  assert.match(platform, /if \(dart\.library\.html\) 'timeline_ad_slot_web\.dart'/);
  assert.match(stub, /SizedBox\.shrink/);
  assert.match(web, /defaultValue: false/);
  assert.match(web, /NINJA_ADMAX_SWITCH_ID/);
  assert.match(web, /'admax-switch'/);
  assert.match(web, /'広告'/);
  assert.match(web, /HtmlElementView/);
});

test("only the explicitly mounted timeline view can request AdMax", () => {
  const browser = read("web/index.html");
  const seo = read("api/seo.js");
  assert.match(browser, /window\.addEventListener\("sharemarium:admax-slot-ready"/);
  assert.match(browser, /window\.location\.hostname === expectedHost/);
  assert.match(browser, /window\.location\.pathname === "\/"/);
  assert.match(browser, /entitlementState !== "ads_allowed"/);
  assert.match(browser, /if \(adRequested\) return/);
  assert.match(browser, /script\.dataset\.ninjaAdmax = "timeline"/);
  assert.doesNotMatch(browser, /googlesyndication|adsbygoogle|ca-pub-/);
  assert.doesNotMatch(seo, /googlesyndication|adsbygoogle|ca-pub-/);
});

test("existing Terms of Service and subscription UI are not changed", () => {
  const flags = read("lib/config/feature_flags.dart");
  assert.match(flags, /subscriptionUiEnabled = false/);
});
