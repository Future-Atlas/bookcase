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


test("featured books persist editorial identity but not third-party description or cover snapshots", () => {
  const service = readFileSync("lib/services/supabase_service.dart", "utf8");
  const start = service.indexOf("Future<bool> adminSaveFeaturedBook(");
  const end = service.indexOf("Future<bool> adminRemoveFeaturedBook(", start);
  assert.ok(start >= 0 && end > start);
  const save = service.slice(start, end);
  assert.match(save, /'book_id': bookId/);
  assert.match(save, /'related_screen_titles': relatedScreenTitles/);
  assert.match(save, /'book_cover_url': ''/);
  assert.match(save, /'book_description': ''/);
  assert.doesNotMatch(save, /'book_description': book\.description/);
  assert.doesNotMatch(save, /'book_cover_url': book\.coverUrl/);

  const model = readFileSync("lib/models/featured_book.dart", "utf8");
  assert.match(model, /coverUrl: ''/);
  assert.match(model, /description: ''/);
  const controller = readFileSync("lib/controllers/book_list_controller.dart", "utf8");
  assert.match(controller, /_hydrateFeaturedBooks/);
  assert.match(controller, /NdlApi\.fetchBookById\(normalizedId\)/);
  assert.match(controller, /OpenBdApi\.enrich\(<Book>\[found\]\)/);
});

test("public featured SEO never republishes unverified legacy cover and description snapshots", () => {
  const seo = readFileSync("api/seo.js", "utf8");
  const start = seo.indexOf("function renderFeaturedBookList(books) {");
  const end = seo.indexOf("function rakutenEnabled()", start);
  assert.ok(start >= 0 && end > start);
  const list = seo.slice(start, end);
  assert.match(list, /book\.book_title/);
  assert.doesNotMatch(list, /book\.book_cover_url/);
  assert.doesNotMatch(list, /book\.book_description/);
});


test("browser Rakuten quota failures trigger local cooldown instead of retry storms", () => {
  const client = readFileSync("lib/api/rakuten_api.dart", "utf8");
  assert.match(client, /_quotaCooldownUntil/);
  assert.match(client, /response\.statusCode == 429/);
  assert.match(client, /response\.statusCode == 503/);
  assert.match(client, /response\.headers\['retry-after'\]/);
  assert.doesNotMatch(client, /_getWithRateLimitRetry/);
  assert.doesNotMatch(client, /Retrying in/);
});
