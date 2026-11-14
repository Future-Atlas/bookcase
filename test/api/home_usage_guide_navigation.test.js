const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = (name) => fs.readFileSync(path.join(__dirname, '../..', name), 'utf8');
const main = read('lib/main.dart');
const home = read('lib/screens/book_list_screen.dart');
const nav = read('lib/widgets/primary_bottom_navigation.dart');
const guide = read('lib/screens/usage_guide_screen.dart');

test('timeline icon is a thick upward outlined triangle', () => {
  assert.match(nav, /timeline-triangle-up/);
  assert.match(nav, /_TimelineTrianglePainter/);
  assert.match(nav, /PaintingStyle\.stroke/);
  assert.match(nav, /strokeWidth = 2\.4/);
  assert.doesNotMatch(nav, /Text\('▽'/);
});

test('signed-in home omits only the guest introduction and hero', () => {
  assert.match(home, /if \(!context\.watch<SupabaseService>\(\)\.isAuthenticated\)\s+_buildTopHeroImage\(\)/);
  assert.match(home, /if \(!context\.watch<SupabaseService>\(\)\.isAuthenticated &&[\s\S]*?_buildServiceIntroduction\(\)/);
  assert.match(home, /_buildSearchBar\(\)/);
  assert.match(home, /_buildGenreSection\(/);
});

test('hamburger menu places a routable usage guide between timeline and settings', () => {
  const p = main.indexOf('value: _HeaderMenuAction.timeline');
  const g = main.indexOf('value: _HeaderMenuAction.usageGuide');
  const s = main.indexOf('value: _HeaderMenuAction.settings');
  assert.ok(p >= 0 && p < g && g < s);
  assert.match(main, /case '\/guide':\s+return 13/);
  assert.match(main, /case 13:\s+return '\/guide'/);
  assert.match(main, /case _HeaderMenuAction\.usageGuide:[\s\S]*?_setCurrentScreenIndex\(13\)/);
  assert.match(main, /_currentScreenIndex == 13\s+\? const UsageGuideScreen/);
});

test('guide covers six current features with actions and limitations', () => {
  for (const section of [
    '読了（投稿機能）', 'My 本棚', '読書カレンダー',
    '読みたい！', 'タイムライン', 'カーラー設定',
  ]) assert.ok(guide.includes(section), section);
  for (const rule of [
    '1,000文字', '同じ書籍', '24時間', '読了済み',
    'フォロワー', 'ダークモード', 'ページカラー', '投稿10・25・50・100件',
  ]) assert.ok(guide.includes(rule), rule);
  assert.match(guide, /ExpansionTile\(/);
  assert.match(guide, /initiallyExpanded: false/);
  assert.match(guide, /'使い方'/);
  assert.match(guide, /'制限・注意点'/);
});

test('usage guide emphasizes instructions and renders small per-line notes', () => {
  assert.match(guide, /fontSize: 18/);
  assert.match(guide, /fontSize: 16, height: 1\.75/);
  assert.match(guide, /entries\[i\]\.limitations\.split\('。'\)/);
  assert.match(guide, /sentence\.trim\(\)\.isNotEmpty/);
  assert.match(guide, /'※ \$\{sentence\.trim\(\)\}。'/);
  assert.match(guide, /fontSize: 12/);
  assert.match(guide, /EdgeInsets\.only\(bottom: 7\)/);
});
