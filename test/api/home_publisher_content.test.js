const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(
  path.join(__dirname, "../../lib/screens/book_list_screen.dart"),
  "utf8",
);

const link = fs.readFileSync(
  path.join(__dirname, "../../lib/widgets/public_posts_link.dart"),
  "utf8",
);

test("home screen explains Sharemarium's original value to human users", () => {
  assert.match(source, /Sharemariumでできること/);
  assert.match(source, /読書体験をレビューとして残す/);
  assert.match(source, /他の読者の感想に触れる/);
  assert.match(source, /次に読む本を見つける/);
  assert.match(source, /あなたの感想や交流が、Sharemariumを作ります。/);
  assert.match(source, /読んだ本を評価するだけでなく/);
  assert.doesNotMatch(source, /ネタバレを含む投稿は明示して公開できます/);
});

test("home service introduction links to public posts and operator information", () => {
  assert.match(source, /PublicPostsLink\(\s*foregroundColor:/);
  assert.match(link, /pushNamed\('\/posts'\)/);
  assert.match(link, /タイムラインを見る/);
  assert.match(source, /pushNamed\('\/about'\)/);
  assert.match(source, /他ユーザーのレビューやリアクションを通じて/);
  assert.match(source, /サービス・運営方針について/);
});

test("service introduction is limited to the real home screen", () => {
  assert.match(
    source,
    /if \(widget\.initialGenre == null &&\s+_controller\.searchQuery\.isEmpty\)\s+_buildServiceIntroduction\(\)/,
  );
});

test("service introduction starts collapsed and can be expanded or collapsed", () => {
  assert.match(source, /bool _isServiceIntroductionExpanded = false;/);
  assert.match(source, /ValueKey\('service-introduction-toggle'\)/);
  assert.match(source, /Icons\.keyboard_arrow_down/);
  assert.match(source, /Icons\.keyboard_arrow_up/);
  assert.match(source, /if \(_isServiceIntroductionExpanded\) \.\.\.\[/);
});
