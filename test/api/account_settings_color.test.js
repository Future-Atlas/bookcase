const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(
  path.join(__dirname, "../../lib/screens/account_settings_screen.dart"),
  "utf8",
);
const colorSource = fs.readFileSync(
  path.join(__dirname, "../../lib/models/profile_page_color.dart"),
  "utf8",
);

test("account settings actions inherit the active profile color", () => {
  assert.match(source, /class _AccountColorTheme extends StatelessWidget/);
  assert.match(source, /activePageColorKey/);
  assert.match(source, /colorScheme: base\.colorScheme\.copyWith\([\s\S]*primary: accountColor/);
  assert.match(source, /listTileTheme:[\s\S]*iconColor: accountColor/);
  assert.match(source, /iconButtonTheme:[\s\S]*foregroundColor: accountColor/);
  assert.match(source, /textButtonTheme:[\s\S]*foregroundColor: accountColor/);
  assert.match(source, /outlinedButtonTheme:[\s\S]*foregroundColor: accountColor/);
  assert.match(source, /filledButtonTheme:[\s\S]*backgroundColor: accountColor/);
  assert.match(source, /colorKey: _pageColorKey/);
  assert.doesNotMatch(source, /FilledButton\.styleFrom\(backgroundColor: Colors\.red\)/);
  assert.doesNotMatch(source, /iconColor: Colors\.red/);
  assert.doesNotMatch(source, /textColor: Colors\.red/);
});

test("post milestones unlock one selected page color at a time", () => {
  const service = fs.readFileSync(
    path.join(__dirname, "../../lib/services/supabase_service.dart"),
    "utf8",
  );
  const migration = fs.readFileSync(
    path.join(
      __dirname,
      "../../supabase/migrations/20261017120000_add_post_milestone_page_color_unlocks.sql",
    ),
    "utf8",
  );
  const progressMigration = fs.readFileSync(
    path.join(
      __dirname,
      "../../supabase/migrations/20261017180000_preserve_page_color_milestone_progress.sql",
    ),
    "utf8",
  );

  assert.match(source, /fetchPageColorAccess\(\)/);
  assert.match(source, /unlockPageColor\(option\.key\)/);
  assert.match(source, /allowTemporarySelection: true/);
  assert.match(source, /冊読了達成！好きな色を\$_colorUnlocksRemaining色解禁できます/);
  assert.match(source, /現在\$_pageColorPostCount冊読了済み/);
  assert.match(source, /あと\$booksRemaining冊読了で解禁されます/);
  assert.match(source, /特典使用後の解禁可能数は\$unlocksAfterSelection色になります/);
  assert.match(source, /取り消し・色の変更は一切出来ません/);
  assert.match(source, /投稿10件・25件・50件・100件/);
  assert.match(service, /current_user_page_color_access/);
  assert.match(service, /unlock_current_user_page_color/);
  assert.match(migration, /private\.page_color_post_unlocks/);
  assert.match(migration, /WHEN[\s\S]*< 10 THEN 0/);
  assert.match(migration, /WHEN[\s\S]*< 25 THEN 1/);
  assert.match(migration, /WHEN[\s\S]*< 50 THEN 2/);
  assert.match(migration, /WHEN[\s\S]*< 100 THEN 3/);
  assert.match(migration, /100\) \/ 50\.0/);
  assert.match(migration, /private\.profile_can_use_page_color/);
  assert.match(progressMigration, /GREATEST\(earned_unlocks, selected_unlocks\) \+ 1/);
  assert.match(progressMigration, /private\.page_color_milestone_for_slot/);
});

test("the second page-color row uses the requested order", () => {
  const optionKeys = [...colorSource.matchAll(/key: '([^']+)'/g)].map(
    (match) => match[1],
  );

  assert.deepEqual(optionKeys.slice(7), [
    "brown",
    "pink",
    "light_blue",
    "orange",
    "yellow_green",
    "red_purple",
    "emerald",
  ]);
});
