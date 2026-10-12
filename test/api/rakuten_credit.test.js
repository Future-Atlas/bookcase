const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (file) => fs.readFileSync(path.join(__dirname, '../..', file), 'utf8');
const snippet = '<a href="https://webservice.rakuten.co.jp/" target="_blank"><img src="https://webservice.rakuten.co.jp/img/credit/200709/credit_22121.gif" border="0" alt="Rakuten Web Service Center" title="Rakuten Web Service Center" width="221" height="21"/></a>';

test('web credit preserves official markup and reserves its original dimensions', () => {
  const source = read('lib/widgets/rakuten_credit_web.dart');
  assert.ok(source.includes(snippet));
  assert.match(source, /width: 221/);
  assert.match(source, /height: 21/);
  assert.match(source, /HtmlElementView/);
});

test('visible home footer places credit directly after copyright', () => {
  const source = read('lib/screens/book_list_screen.dart');
  const copyright = source.indexOf('© 2026 Sharemarium. All rights reserved.');
  const credit = source.indexOf('const RakutenCredit()', copyright);
  const powered = source.indexOf('Powered by Supabase', copyright);
  assert.ok(copyright >= 0 && credit > copyright && credit < powered);
});

test('server rendered footer also includes official credit below copyright', () => {
  const source = read('api/seo.js');
  assert.ok(source.includes(snippet));
  assert.ok(source.indexOf(snippet) > source.indexOf('© 2026 ${SITE_BRAND}'));
});
