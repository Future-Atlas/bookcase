const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(
  path.join(__dirname, "../../lib/screens/account_settings_screen.dart"),
  "utf8",
);

test("account settings actions inherit the active profile color", () => {
  assert.match(source, /class _AccountColorTheme extends StatelessWidget/);
  assert.match(source, /activePageColorKey/);
  assert.match(source, /colorScheme: base\.colorScheme\.copyWith\([\s\S]*primary: accountColor/);
  assert.match(source, /colorKey: _pageColorKey/);
  assert.doesNotMatch(source, /FilledButton\.styleFrom\(backgroundColor: Colors\.red\)/);
  assert.doesNotMatch(source, /iconColor: Colors\.red/);
  assert.doesNotMatch(source, /textColor: Colors\.red/);
});
