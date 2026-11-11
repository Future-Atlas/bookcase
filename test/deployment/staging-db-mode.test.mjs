import assert from 'node:assert/strict';
import { test } from 'node:test';
import { modeForChanges, selectMode } from '../../scripts/staging-db-deployment-mode.mjs';

const good = () => ({
  GITHUB_ACTIONS: 'true',
  GITHUB_REPOSITORY: 'Future-Atlas/bookcase',
  GITHUB_REF: 'refs/heads/develop',
  GITHUB_EVENT_NAME: 'push',
  BEFORE_SHA: 'a'.repeat(40),
  GITHUB_SHA: 'b'.repeat(40),
});

test('config/CLI/workflow only changes never apply remote DB changes automatically', () => {
  assert.equal(modeForChanges('push', 'false', [
    'supabase/config.toml',
    'scripts/deploy-staging-db.mjs',
    '.github/workflows/supabase-deploy-staging.yaml',
    'package-lock.json',
  ]), 'plan');
});

test('a real migration or function update still applies to staging on a push', () => {
  for (const path of [
    'supabase/migrations/20261110000000_example.sql',
    'supabase/functions/billing-checkout/index.ts',
    'supabase/functions/_shared/security.ts',
  ]) {
    assert.equal(modeForChanges('push', 'false', [path]), 'apply');
  }
});

test('manual dispatch defaults to plan and requires explicit true to apply', () => {
  assert.equal(modeForChanges('workflow_dispatch', '', []), 'plan');
  assert.equal(modeForChanges('workflow_dispatch', 'false', []), 'plan');
  assert.equal(modeForChanges('workflow_dispatch', 'true', []), 'apply');
});

test('rejects a forged repo, branch, empty push base, or unknown event', () => {
  const bad = [
    { GITHUB_REPOSITORY: 'untrusted/fork' },
    { GITHUB_REF: 'refs/heads/main' },
    { GITHUB_ACTIONS: 'false' },
    { GITHUB_EVENT_NAME: 'pull_request' },
    { BEFORE_SHA: '0'.repeat(40) },
    { GITHUB_SHA: 'malformed' },
  ];
  for (const override of bad) {
    let diffCalled = false;
    assert.throws(() => selectMode({
      env: { ...good(), ...override },
      getChangedPaths: () => { diffCalled = true; return []; },
    }));
    assert.equal(diffCalled, false);
  }
});

test('diff failures abort instead of silently changing deployment mode', () => {
  assert.throws(() => selectMode({
    env: good(), getChangedPaths: () => { throw new Error('git diff failed'); },
  }), /git diff failed/);
});

test('approved push obtains exact validated commits and does not apply for tooling only', () => {
  const env = good();
  assert.equal(selectMode({
    env,
    getChangedPaths: (before, after) => {
      assert.equal(before, env.BEFORE_SHA);
      assert.equal(after, env.GITHUB_SHA);
      return ['supabase/config.toml'];
    },
  }), 'plan');
});
