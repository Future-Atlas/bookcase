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

  assert.match(main, /bottomNavigationBar: _currentScreenIndex == 0 \|\|\s*_currentScreenIndex == 1/);
  assert.match(main, /_currentScreenIndex == 5 && _viewedProfileId != null/);
  assert.match(main, /accentColor: headerColor/);
  assert.match(main, /onTimeline: \(\) => Navigator\.of\(context\)\.pushNamed\('\/posts'\)/);
  assert.match(timeline, /bottomNavigationBar: PrimaryBottomNavigation\(/);
  assert.match(footer, /ValueKey\('timeline-triangle-up'\)/);
  assert.match(footer, /_TimelineTrianglePainter/);
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

test("other users retain the footer in both main shell and standalone profile routes", () => {
  const main = read("lib/main.dart");
  const profile = read("lib/screens/user_profile_screen.dart");
  const footer = read("lib/widgets/primary_bottom_navigation.dart");

  assert.match(main, /_currentScreenIndex == 5 && _viewedProfileId != null/);
  assert.match(main, /_currentScreenIndex == 1 \? 2 : -1/);
  assert.match(profile, /bottomNavigationBar: widget\.showAppBar && widget\.profileId != null/);
  assert.match(profile, /selectedIndex: -1/);
  assert.match(profile, /accentColor: profileHeaderColor/);
  assert.match(profile, /pushNamedAndRemoveUntil\('\/posts'/);
  assert.match(profile, /pushNamedAndRemoveUntil\('\/mypage'/);
  assert.match(footer, /height: 64/);
});
