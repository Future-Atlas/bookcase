const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (name) => fs.readFileSync(path.join(__dirname, '../..', name), 'utf8');

test('the selected book keeps its image renderer on the timer screen', () => {
  const timer = read('lib/screens/reading_timer_screen.dart');
  assert.match(timer, /import '\.\.\/widgets\/book_cover_image\.dart';/);
  assert.match(timer, /BookCoverImage\(book: book\)/);
  assert.match(timer, /coverSource: session\.bookCoverSource,/);
  assert.doesNotMatch(timer, /ReadingCoverArt\(url: book\.coverUrl\)/);
});

test('reading session saves cover provenance for resume', () => {
  const service = read('lib/services/reading_session_service.dart');
  assert.match(service, /'p_book_cover_url': book\.coverUrl,/);
  assert.match(service, /'p_book_cover_source': book\.coverSource,/);
});

test('calendar reading badges permit original HTTPS images without CORS on web', () => {
  const source = read('lib/widgets/reading_cover_art.dart');
  assert.match(source, /WebHtmlElementStrategy\.prefer/);
  assert.match(source, /parsed\.scheme == 'https'/);
  assert.match(source, /fit: BoxFit\.contain/);
});
