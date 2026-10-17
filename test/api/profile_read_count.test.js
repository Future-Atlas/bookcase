const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(
  path.join(__dirname, "../../lib/screens/user_profile_screen.dart"),
  "utf8",
);

test("posts and My bookshelf show the shared completed-book count", () => {
  assert.match(source, /Widget _buildReadCountHeader\(\)/);
  assert.match(source, /'\$readCount冊　読了'/);
  assert.match(
    source,
    /Widget _buildPostsTab\(\)[\s\S]*?_buildReadCountHeader\(\)/,
  );
  assert.match(
    source,
    /Widget _buildReadBooksTab\(\)[\s\S]*?_buildReadCountHeader\(\)/,
  );
  assert.match(source, /_profile\?\.readCount \?\? _userPosts\.length/);
});
