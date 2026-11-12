const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (name) => fs.readFileSync(path.join(__dirname, '../..', name), 'utf8');

test('after required consent and MFA, signed-in users restore an active timer', () => {
  const main = read('lib/main.dart');
  const gate = read('lib/screens/reading_timer_resume_gate.dart');
  assert.equal(
    (main.match(/ReadingTimerResumeGate\(child: MainNavigationShell\(\)\)/g) || []).length,
    2,
  );
  assert.match(gate, /ReadingSessionService\(\)\.activeSession\(\)/);
  assert.match(gate, /resuming: active/);
  assert.match(gate, /onFinished:/);
  assert.match(gate, /onDefer:/);
  assert.match(gate, /_checkedUserId = null/);
  assert.match(gate, /_deferred = false/);
});

test('an already-running timer can be stopped instead of getting stuck on start error', () => {
  const timer = read('lib/screens/reading_timer_screen.dart');
  assert.match(timer, /existing = await _service\.activeSession\(\)/);
  assert.match(timer, /_active = existing/);
  assert.match(timer, /_startTicking\(\)/);
  assert.match(timer, /widget\.onFinished!\(\)/);
  assert.match(timer, /widget\.onDefer/);
  assert.match(timer, /_service\.finish\(_active!\.id\)/);
});

test('calendar book selection always resumes an existing timer first', () => {
  const profile = read('lib/screens/user_profile_screen.dart');
  assert.match(
    profile,
    /if \(await _resumeActiveCalendarTimerIfNeeded\(\)\) return;[\s\S]*ProfileBookSearchScreen\(calendarSelection: true\)/,
  );
  assert.match(
    profile,
    /if \(book == null \|\| !mounted\) return;[\s\S]*if \(await _resumeActiveCalendarTimerIfNeeded\(\)\) return;/,
  );
  assert.match(profile, /active = await _readingSessionService\.activeSession\(\)/);
  assert.match(profile, /await _resumeCalendarTimer\(active\)/);
  assert.match(profile, /Fail closed/);
});
