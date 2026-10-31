const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.join(__dirname, "../..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

test("featured books use an admin-only curated table with public active reads", () => {
  const migration = read(
    "supabase/migrations/20261013180000_add_featured_books.sql",
  );
  assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.featured_books/);
  assert.match(migration, /Administrators can manage featured books/);
  assert.match(migration, /starts_at IS NULL/);
  assert.match(migration, /ends_at IS NULL/);
  assert.match(migration, /related_screen_titles TEXT\[\]/);
});

test("home, admin, SEO, routing and sitemap integrate featured books", () => {
  assert.match(read("lib/screens/book_list_screen.dart"), /featured-books-link/);
  assert.match(read("lib/widgets/featured_books_admin_panel.dart"), /注目書籍の管理/);
  assert.match(read("api/seo.js"), /decodedPath === "\/featured-books"/);
  assert.match(read("api/sitemap.js"), /dynamicFeaturedUrls/);
  assert.match(read("vercel.json"), /featured-books/);
});

test("direct book paths are handed to Flutter's real book dialog", () => {
  const main = read("lib/main.dart");
  const routes = read("lib/screens/public_post_routes.dart");
  const screen = read("lib/screens/book_list_screen.dart");
  assert.match(routes, /BookListScreen\(initialBookId: segments\[1\]\)/);
  assert.doesNotMatch(main, /initialBookId: _bookIdFromPath/);
  assert.match(screen, /NdlApi\.fetchBookById\(initialBookId\)/);
  assert.match(screen, /routeInformationUpdated/);
});
