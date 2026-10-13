const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

function read(file) {
  return fs.readFileSync(path.join(__dirname, "../..", file), "utf8");
}

test("public posts are accessible from a persistent, visible header link", () => {
  const main = read("lib/main.dart");
  const link = read("lib/widgets/public_posts_link.dart");

  // Do not hide this behind the hamburger menu.
  assert.match(main, /width: headerSideWidth,\s*child: Row\(/);
  assert.match(main, /Expanded\(\s*child: PublicPostsLink\(\s*compact: true,/);
  assert.match(main, /import 'widgets\/public_posts_link.dart';/);
  assert.match(link, /key: const ValueKey\('header-public-posts-link'\)/);
  assert.match(link, /child: Text\(\s*'タイムライン',/);
  assert.match(link, /Navigator\.of\(context\)\.pushNamed\('\/posts'\)/);
});

test("hamburger menu also has an explicitly named posts destination", () => {
  const main = read("lib/main.dart");
  assert.match(main, /enum _HeaderMenuAction \{ home, posts,/);
  assert.match(main, /value: _HeaderMenuAction\.posts,\s*child: Text\(\s*'タイムライン',/);
  assert.match(main, /case _HeaderMenuAction\.posts:\s*Navigator\.of\(context\)\.pushNamed\('\/posts'\);/);
});

test("home CTA uses タイムラインを見る and routes to the existing public index", () => {
  const home = read("lib/screens/book_list_screen.dart");
  const link = read("lib/widgets/public_posts_link.dart");
  const routes = read("lib/screens/public_post_routes.dart");
  const main = read("lib/main.dart");

  assert.match(home, /const PublicPostsLink\(\)/);
  assert.match(link, /label: const Text\('タイムラインを見る'\)/);
  assert.match(routes, /if \(segments\.length == 1\) \{\s*screen = const PublicPostsScreen\(\);/);
  assert.match(main, /onGenerateRoute: publicPostRoute,/);
  assert.match(routes, /title: const Text\('タイムライン'\)/);
  // No extra login or authentication requirement is introduced by the shortcut.
  assert.doesNotMatch(link, /isAuthenticated|login|token|authGate/);
});
