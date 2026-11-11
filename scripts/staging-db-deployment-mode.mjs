import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// A CLI-only/config-only change must never trigger remote DB writes on merge.
// Actual migration or Edge Function source changes retain automatic staging
// application. Manual dispatch needs an explicit apply_changes=true.
export function modeForChanges(eventName, manualApply, changedPaths = []) {
  if (eventName === 'workflow_dispatch') {
    return manualApply === 'true' ? 'apply' : 'plan';
  }
  if (eventName !== 'push' || !Array.isArray(changedPaths)) {
    throw new Error('Unsupported event or invalid changes; no deployment allowed.');
  }
  return changedPaths.some(path =>
    path.startsWith('supabase/migrations/') ||
    path.startsWith('supabase/functions/')
  ) ? 'apply' : 'plan';
}

export function selectMode({
  env = process.env,
  getChangedPaths = (before, after) => {
    const result = execFileSync(
      'git', ['diff', '--name-only', before, after, '--', 'supabase/migrations', 'supabase/functions'],
      { encoding: 'utf8' },
    );
    return result.split('\n').map(s => s.trim()).filter(Boolean);
  },
} = {}) {
  if (env.GITHUB_ACTIONS !== 'true' ||
      env.GITHUB_REPOSITORY !== 'Future-Atlas/bookcase' ||
      env.GITHUB_REF !== 'refs/heads/develop') {
    throw new Error('Cannot select a deployment mode outside approved staging CI.');
  }

  if (env.GITHUB_EVENT_NAME === 'workflow_dispatch') {
    return modeForChanges('workflow_dispatch', env.MANUAL_APPLY);
  }
  if (env.GITHUB_EVENT_NAME !== 'push') {
    throw new Error('Only approved push and manual events are supported.');
  }
  const before = env.BEFORE_SHA || '';
  const after = env.GITHUB_SHA || '';
  if (!/^[a-f0-9]{40}$/.test(before) ||
      !/^[a-f0-9]{40}$/.test(after) ||
      before === '0'.repeat(40)) {
    throw new Error('Cannot verify the push diff; refusing to apply or skip migrations.');
  }
  return modeForChanges('push', 'false', getChangedPaths(before, after));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const output = process.env.GITHUB_OUTPUT;
    if (!output) throw new Error('GITHUB_OUTPUT is required for staging deployment.');
    const mode = selectMode();
    appendFileSync(output, 'mode=' + mode + '\n');
    process.stdout.write('Staging database deployment mode: ' + mode + '\n');
  } catch (error) {
    process.stderr.write('Staging deployment mode could not be verified; stopped.\n');
    process.exitCode = 1;
  }
}
