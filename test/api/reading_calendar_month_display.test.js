const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (name) => fs.readFileSync(path.join(__dirname, '../..', name), 'utf8');
const calendar = read('lib/screens/reading_calendar_tab.dart');
const timer = read('lib/screens/reading_timer_screen.dart');
const month = read('lib/utils/reading_calendar_month.dart');

test('calendar starts Sunday and uses unique monthly book groups as day badges', () => {
  assert.match(calendar, /sundayFirstCalendarOffset\(_month\)/);
  assert.match(calendar, /\['日', '月', '火', '水', '木', '金', '土'\]/);
  assert.match(calendar, /summarizeReadingDayBooks\(_sessionsFor\(day\), day\)/);
  assert.match(calendar, /_roundCover\(book\.session, size: side\)/);
  assert.match(calendar, /reading-calendar-book-/);
  assert.match(calendar, /books\.take\(visibleCount\)/);
  assert.match(calendar, /\+\$remaining/);
  assert.doesNotMatch(calendar, /Icon\(Icons\.circle, size: 10/);
});

test('timer disclaimers move into the monthly calendar heading and total is computed', () => {
  assert.doesNotMatch(timer, /計測開始・終了時刻はサーバーで記録されます。/);
  assert.doesNotMatch(timer, /過去の記録を追加・編集することはできません。/);
  assert.match(timer, /1回の計測は最大24時間です。/);
  assert.match(calendar, /※ 過去の記録を追加・編集することはできません。/);
  assert.ok(calendar.indexOf('reading-calendar-no-history-edit-note') <
      calendar.indexOf("'この月の読書記録'"));
  assert.match(calendar, /reading-calendar-month-total/);
  assert.match(calendar, /ReadingSession\.durationLabel\(totalReadingDurationInMonth\(_sessions, _month\)\)/);
  assert.match(month, /Duration\(seconds: accumulated\.inSeconds\)/);
});
