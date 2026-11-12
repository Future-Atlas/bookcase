const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = file => fs.readFileSync(path.join(__dirname, '../..', file), 'utf8');

test('Flutter home footer renders the official Rakuten credit in Rakuten builds', () => {
  const source = read('lib/screens/book_list_screen.dart');
  const copyright = source.indexOf('© 2026 Sharemarium. All rights reserved.');
  const credit = source.indexOf('const CatalogCredit()', copyright);
  const powered = source.indexOf('Powered by Supabase', copyright);
  assert.ok(copyright >= 0 && credit > copyright && credit < powered);
  const widget = read('lib/widgets/catalog_credit.dart');
  assert.match(widget, /RakutenCredit\(\)/);
  assert.match(widget, /width: double\.infinity/);
  assert.match(widget, /Center\(child: RakutenCredit\(\)\)/);
  assert.match(widget, /楽天ブックス（楽天ウェブサービス）/);
  const badge = read('lib/widgets/rakuten_credit_web.dart');
  assert.match(badge, /credit_22121\.gif/);
  assert.match(badge, /Rakuten Web Services Attribution Snippet/);
  assert.match(badge, /textAlign = 'center'/);
  assert.match(widget, /ndlsearch.ndl.go.jp/);
  assert.match(widget, /creativecommons.org\/licenses\/by\/4.0/);
  assert.match(widget, /openbd.jp/);
});

test('canonical book detail uses the provenance-aware cover renderer', () => {
  const source = read('lib/widgets/book_detail_dialog.dart');
  assert.match(source, /child: BookCoverImage\(book: book\)/);
  assert.doesNotMatch(source, /Image\.network\(\s*book\.coverUrl/);
});
test('crawler footer credits the NDL records without Rakuten Web Services', () => {
  const source = read('api/seo.js');
  const footer = source.slice(source.indexOf('<footer>'), source.indexOf('</footer>')+9);
  assert.match(footer, /ndlsearch.ndl.go.jp/);
  assert.match(footer, /creativecommons.org\/licenses\/by\/4.0/);
  assert.doesNotMatch(footer, /webservice.rakuten.co.jp/);
});
