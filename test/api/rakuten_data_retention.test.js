const assert = require("node:assert/strict");
const test = require("node:test");
const { readFileSync } = require("node:fs");

test("new book reviews keep user-authored text without copying vendor descriptions forever", () => {
  const source = readFileSync("lib/services/supabase_service.dart", "utf8");
  const start = source.indexOf("Future<bool> createPost({");
  const end = source.indexOf("Future<bool> deleteOwnPost(", start);
  assert.ok(start >= 0 && end > start);
  const createPost = source.slice(start, end);
  assert.match(createPost, /'book_id': book\.id/);
  assert.match(createPost, /'book_description': ''/);
  assert.match(createPost, /'comment': normalizedComment/);
  assert.match(createPost, /'rating': rating/);
  assert.doesNotMatch(createPost, /'book_description': book\.description/);
});

test("the Rakuten cache is bounded in time while reviews and bookshelves retain their own IDs", () => {
  const source = readFileSync("lib/api/rakuten_api.dart", "utf8");
  assert.match(source, /_bookCacheTtl = Duration\(minutes: 15\)/);
  assert.match(source, /cached\.expiresAt\.isAfter\(DateTime\.now\(\)\.toUtc\(\)\)/);
  const db = readFileSync("lib/services/supabase_service.dart", "utf8");
  assert.match(db, /'book_id': bookId/);
  assert.match(db, /'comment': normalizedComment/);
});

test("price is not shown in the Rakuten purchase UI", () => {
  const source = readFileSync("lib/widgets/rakuten_book_link.dart", "utf8");
  assert.match(source, /楽天ブックスで購入する/);
  assert.match(source, /広告・楽天アフィリエイトリンク/);
  assert.doesNotMatch(source, /_priceLabel/);
  assert.doesNotMatch(source, /destination\.itemPrice/);
});
