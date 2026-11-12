const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

function read(file) {
  return fs.readFileSync(path.join(__dirname, "../..", file), "utf8");
}

test("timeline, home and profile are provided by the persistent footer", () => {
  const main = read("lib/main.dart");
  const timeline = read("lib/screens/public_post_routes.dart");
  const footer = read("lib/widgets/primary_bottom_navigation.dart");

  assert.match(main, /bottomNavigationBar: _currentScreenIndex == 0 \|\| _currentScreenIndex == 1/);
  assert.match(main, /onTimeline: \(\) => Navigator\.of\(context\)\.pushNamed\('\/posts'\)/);
  assert.match(timeline, /bottomNavigationBar: PrimaryBottomNavigation\(/);
  assert.match(footer, /const Text\('▽'/);
  assert.match(footer, /Icons\.home_outlined/);
  assert.match(footer, /Icons\.person_outline/);
  assert.doesNotMatch(main, /child: PublicPostsLink\(/);
});

test("hamburger menu includes the timeline destination", () => {
  const main = read("lib/main.dart");
  assert.match(main, /value: _HeaderMenuAction\.timeline/);
  assert.match(main, /case _HeaderMenuAction\.timeline:/);
});

test("home CTA uses タイムラインを見る and routes to the existing public index", () => {
  const home = read("lib/screens/book_list_screen.dart");
  const link = read("lib/widgets/public_posts_link.dart");
  const routes = read("lib/screens/public_post_routes.dart");
  const main = read("lib/main.dart");

  assert.match(home, /PublicPostsLink\(\s*foregroundColor:/);
  assert.match(link, /label: const Text\('タイムラインを見る'\)/);
  assert.match(routes, /if \(segments\.length == 1\) \{\s*screen = const PublicPostsScreen\(\);/);
  assert.match(main, /onGenerateRoute: publicPostRoute,/);
  assert.match(routes, /title: const Text\('タイムライン'\)/);
  assert.match(home, /sectionHeading: true/);
  assert.match(
    home,
    /if \(widget\.timelineOnly\)[\s\S]*?_buildTimeline\(\s*height: constraints\.maxHeight,\s*embedded: false,/,
  );
  assert.match(home, /_buildTimeline\(\),/);
  assert.match(home, /if \(!embedded\) \{\s*return SizedBox\(/);
  // No extra login or authentication requirement is introduced by the shortcut.
  assert.doesNotMatch(link, /isAuthenticated|login|token|authGate/);
});
