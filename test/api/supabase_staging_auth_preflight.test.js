const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const load = import('../../scripts/preflight-supabase-staging.mjs');
const read = p => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8');

function goodEnv() {
  return {
    GITHUB_ACTIONS: 'true',
    GITHUB_REPOSITORY: 'Future-Atlas/bookcase',
    GITHUB_REF: 'refs/heads/develop',
    SUPABASE_PROJECT_ID: 'wpoigmywpewrrbudqhgh',
    SUPABASE_ACCESS_TOKEN: 'sbp_fake-token-for-unit-tests',
    SUPABASE_DB_PASSWORD: 'fake-password-for-unit-tests',
    SUPABASE_DB_URL: 'postgresql://postgres.wpoigmywpewrrbudqhgh:fake-password-for-unit-tests@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres',
  };
}

test('rejects wrong target and missing credentials before any request', async () => {
  const { preflightStagingSupabase } = await load;
  for (const [name, value] of [
    ['GITHUB_ACTIONS', 'false'],
    ['GITHUB_REF', 'refs/heads/main'],
    ['GITHUB_REPOSITORY', 'untrusted/fork'],
    ['SUPABASE_PROJECT_ID', 'abcdefghijklmnopqrst'],
    ['SUPABASE_ACCESS_TOKEN', ''],
    ['SUPABASE_ACCESS_TOKEN', 'sb_publishable_test'],
    ['SUPABASE_DB_PASSWORD', ''],
    ['SUPABASE_DB_URL', ''],
  ]) {
    let called = false;
    await assert.rejects(
      preflightStagingSupabase({
        env: { ...goodEnv(), [name]: value },
        fetchImpl: async () => { called = true; throw Error('network should not be used'); },
      }),
    );
    assert.equal(called, false, name + ' must fail locally');
  }
});

test('only one read-only Management API GET verifies staging project ref', async () => {
  const { preflightStagingSupabase } = await load;
  const env = goodEnv();
  let calls = 0;
  const result = await preflightStagingSupabase({
    env,
    fetchImpl: async (url, options) => {
      calls++;
      assert.equal(url, 'https://api.supabase.com/v1/projects/' + env.SUPABASE_PROJECT_ID);
      assert.equal(options.method, 'GET');
      assert.equal(options.headers.Authorization, 'Bearer ' + env.SUPABASE_ACCESS_TOKEN);
      assert.equal(options.redirect, 'error');
      assert.ok(options.signal);
      assert.ok(!JSON.stringify(options).includes(env.SUPABASE_DB_PASSWORD));
      return { status: 200, ok: true, json: async () => ({ ref: env.SUPABASE_PROJECT_ID }) };
    },
  });
  assert.equal(calls, 1);
  assert.equal(result, true);
});

test('bad PAT / wrong project / network errors cannot leak secrets', async () => {
  const { preflightStagingSupabase } = await load;
  const env = goodEnv();
  for (const status of [401, 403, 404, 429, 500]) {
    await assert.rejects(
      preflightStagingSupabase({
        env,
        fetchImpl: async () => ({
          status,
          ok: false,
          json: async () => ({ secret: env.SUPABASE_ACCESS_TOKEN }),
        }),
      }),
      error => error.message.includes(String(status)) &&
        !error.message.includes(env.SUPABASE_ACCESS_TOKEN) &&
        !error.message.includes(env.SUPABASE_DB_PASSWORD),
    );
  }
  await assert.rejects(
    preflightStagingSupabase({
      env,
      fetchImpl: async () => { throw Error(env.SUPABASE_ACCESS_TOKEN); },
    }),
    error => !error.message.includes(env.SUPABASE_ACCESS_TOKEN),
  );
  await assert.rejects(
    preflightStagingSupabase({
      env,
      fetchImpl: async () => ({
        status: 200, ok: true,
        json: async () => ({ id: 'differentprojectref' }),
      }),
    }),
    /reference mismatch/,
  );
});

test('staging workflow executes read-only probe before CLI link or DB apply', () => {
  const workflow = read('.github/workflows/supabase-deploy-staging.yaml');
  const target = workflow.indexOf('node scripts/deploy-staging-db.mjs guard');
  const probe = workflow.indexOf('node scripts/preflight-supabase-staging.mjs');
  const deploy = workflow.indexOf('node scripts/deploy-staging-db.mjs "$DEPLOY_MODE"');
  assert.ok(target >= 0 && probe > target && deploy > probe);
  assert.match(workflow, /name: staging/);
  const docs = read('docs/staging_database_deployment.md');
  assert.match(docs, /Supabase Management APIの読み取り専用GET/);
});
