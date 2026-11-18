const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = (name) =>
  fs.readFileSync(path.join(__dirname, '../..', name), 'utf8');
const main = read('lib/main.dart');
const controller = read('lib/controllers/book_list_controller.dart');
const home = read('lib/screens/book_list_screen.dart');
const stack = read('lib/widgets/persistent_home_navigation_stack.dart');

test('all menu pages use a mounted Home cache, not only the usage guide', () => {
  assert.match(main, /PersistentHomeNavigationStack\(/);
  assert.match(main, /showHome: _currentScreenIndex == 0 \|\|\s+_currentScreenIndex == 13/);
  assert.match(main, /other: AnimatedSwitcher\(/);
  assert.match(stack, /IndexedStack\(/);
  assert.match(stack, /_hasOpenedHome/);
  assert.match(stack, /HomeGuideNavigationStack\(/);
  assert.match(stack, /if \(widget\.showHome\) const SizedBox\.shrink\(\) else widget\.other/);
});

test('cached Home is replaced on sign-out or account change', () => {
  assert.match(main, /cacheKey: service\.isAuthenticated/);
  assert.match(main, /service\.activeProfileId/);
  assert.match(stack, /oldWidget\.cacheKey != widget\.cacheKey/);
  assert.match(stack, /key: ValueKey\(widget\.cacheKey\)/);
});

test('API refresh keeps previous Home cards and page cursors on failures', () => {
  assert.match(controller, /Keep previously fetched Home cards visible/);
  assert.match(controller, /if \(accessChanged\)/);
  for (const genre of ['recommended', 'japanese', 'western', 'popular']) {
    assert.match(controller, new RegExp(
      'if \\(books\\.isNotEmpty \\|\\| ' + genre + 'Books\\.isEmpty\\)'
    ));
    assert.match(controller, new RegExp(
      'if \\(' + genre + 'Books\\.isEmpty\\) hasMore'
    ));
  }
  assert.match(controller, /Preserve any previous featured covers/);
  assert.match(controller, /Retain the last working timeline/);
  assert.match(controller, /fresh\.coverUrl\.trim\(\)\.isNotEmpty/);
});

test('popular API error has an explicit retry action', () => {
  assert.match(controller, /Future<void> retryPopular\(\) async/);
  assert.match(home, /onRetry: \(\) => unawaited\(_controller\.retryPopular\(\)\)/);
});
