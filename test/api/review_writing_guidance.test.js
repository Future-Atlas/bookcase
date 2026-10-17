const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(
  path.join(__dirname, "../../lib/widgets/post_composer_dialog.dart"),
  "utf8",
);
const serviceSource = fs.readFileSync(
  path.join(__dirname, "../../lib/services/supabase_service.dart"),
  "utf8",
);

test("review composer gives user-centered prompts for substantive reviews", () => {
  assert.match(source, /印象に残った場面、その理由、読後に考えたこと/);
  assert.match(source, /自分の言葉で書いてみましょう/);
  assert.match(source, /1000字以内で、自由に感想を記入してください/);
  assert.match(source, /誹謗中傷や個人情報を記載した場合/);
  assert.match(source, /投稿が削除されることがあります/);
  assert.match(source, /maxLength: _postCommentMaxLength/);
  assert.match(source, /const int _postCommentMaxLength = 1000/);
});

test("review composer does not impose an AdSense-oriented minimum length", () => {
  assert.doesNotMatch(source, /80文字以上|120文字以上|AdSense/);
  assert.match(source, /if \(review\.isEmpty\)/);
});

test("review composer explains required fields and confirms completion", () => {
  assert.match(source, /if \(rating <= 0\)/);
  assert.match(source, /評価が付いていないので、投稿できません/);
  assert.match(source, /感想が未入力なので、投稿できません/);
  assert.match(source, /投稿が完了しました！/);
  assert.doesNotMatch(source, /感想を入力してください/);
  assert.doesNotMatch(source, /レビューを投稿しました/);
});

test("edit dialog title uses the same red as the submit action", () => {
  assert.match(source, /'投稿を編集',[\s\S]*color: Color\(0xFFFF3B30\)/);
});

test("post creation and editing enforce the same 1000 character limit", () => {
  const postMethods = serviceSource.slice(
    serviceSource.indexOf("Future<bool> createPost"),
    serviceSource.indexOf("Future<bool> isBookFavoritedByCurrentUser"),
  );
  assert.equal((postMethods.match(/maxLength: 1000/g) || []).length, 4);
  assert.doesNotMatch(postMethods, /maxLength: 3000/);
});
