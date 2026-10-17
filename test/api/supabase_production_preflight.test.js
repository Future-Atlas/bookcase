const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const preflight = import("../../scripts/preflight-supabase-production.mjs");
const goodEnv = () => ({
  GITHUB_ACTIONS: "true",
  GITHUB_REPOSITORY: "Future-Atlas/bookcase",
  GITHUB_REF: "refs/heads/main",
  SUPABASE_PROJECT_ID: "abcdefghijklmnopqrst",
  SUPABASE_ACCESS_TOKEN: "sbp_unit-test-not-a-real-token",
  SUPABASE_DB_PASSWORD: "test-password-never-print",
});

test("production preflight rejects wrong branch or repository before any network request", async () => {
  const { preflightProductionSupabase } = await preflight;
  for (const [name, value] of [
    ["GITHUB_ACTIONS", "false"],
    ["GITHUB_REPOSITORY", "somebody/fork"],
    ["GITHUB_REF", "refs/heads/develop"],
    ["SUPABASE_PROJECT_ID", "wpoigmywpewrrbudqhgh"],
    ["SUPABASE_PROJECT_ID", ""],
    ["SUPABASE_PROJECT_ID", "staging"],
    ["SUPABASE_PROJECT_ID", '"abcdefghijklmnopqrst"'],
    ["SUPABASE_PROJECT_ID", "abcdefghijklmnopqrst "],
    ["SUPABASE_ACCESS_TOKEN", ""],
    ["SUPABASE_ACCESS_TOKEN", "sb_publishable_not-a-PAT"],
    ["SUPABASE_ACCESS_TOKEN", " sbp_with-leading-whitespace"],
    ["SUPABASE_DB_PASSWORD", ""],
  ]) {
    let requests = 0;
    await assert.rejects(
      preflightProductionSupabase({
        env: { ...goodEnv(), [name]: value },
        fetchImpl: async () => {
          requests++;
          throw new Error("should never fetch");
        },
      }),
      Error,
      name + " must be rejected",
    );
    assert.equal(requests, 0, name + " must not cause a network call");
  }
});

test("read-only probe verifies the specific production project and never sends the DB password", async () => {
  const { preflightProductionSupabase } = await preflight;
  const env = goodEnv();
  let requests = 0;
  const result = await preflightProductionSupabase({
    env,
    fetchImpl: async (url, options) => {
      requests++;
      assert.equal(url, "https://api.supabase.com/v1/projects/abcdefghijklmnopqrst");
      assert.equal(options.method, "GET");
      assert.equal(options.headers.Authorization, "Bearer " + env.SUPABASE_ACCESS_TOKEN);
      assert.equal(options.redirect, "error");
      assert.ok(options.signal);
      assert.ok(!JSON.stringify(options).includes(env.SUPABASE_DB_PASSWORD));
      return {
        status: 200,
        ok: true,
        json: async () => ({ id: "internal-project-id", ref: env.SUPABASE_PROJECT_ID }),
      };
    },
  });
  assert.equal(result, true);
  assert.equal(requests, 1);
});

test("expired PAT, wrong scope or wrong ref cannot pass and never leak credentials", async () => {
  const { preflightProductionSupabase } = await preflight;
  const env = goodEnv();
  for (const status of [401, 403, 404, 429, 500]) {
    await assert.rejects(
      preflightProductionSupabase({
        env,
        fetchImpl: async () => ({
          status,
          ok: false,
          json: async () => ({
            secret: env.SUPABASE_ACCESS_TOKEN,
            databasePassword: env.SUPABASE_DB_PASSWORD,
          }),
        }),
      }),
      error => {
        assert.ok(error.message.includes(String(status)));
        assert.ok(!error.message.includes(env.SUPABASE_ACCESS_TOKEN));
        assert.ok(!error.message.includes(env.SUPABASE_DB_PASSWORD));
        return true;
      },
    );
  }
});

test("network errors and response mismatches stop without leaking data", async () => {
  const { preflightProductionSupabase } = await preflight;
  const env = goodEnv();
  await assert.rejects(
    preflightProductionSupabase({
      env,
      fetchImpl: async () => { throw new Error(env.SUPABASE_ACCESS_TOKEN); },
    }),
    error => !error.message.includes(env.SUPABASE_ACCESS_TOKEN),
  );
  await assert.rejects(
    preflightProductionSupabase({
      env,
      fetchImpl: async () => ({
        status: 200,
        ok: true,
        json: async () => ({ id: "differentproductionref" }),
      }),
    }),
    /project ref did not match/,
  );
});

test("production workflow checks credentials before any Supabase link, db push, or functions deployment", () => {
  const workflow = fs.readFileSync(
    path.join(__dirname, "../../.github/workflows/supabase-deploy.yaml"),
    "utf8",
  );
  const verify = workflow.indexOf("node scripts/preflight-supabase-production.mjs");
  const link = workflow.indexOf('supabase link --project-ref');
  const deployMigrations = workflow.indexOf("- name: Deploy database migrations");
  const deployFunctions = workflow.indexOf("- name: Deploy edge functions");
  assert.ok(verify > 0 && verify < link);
  assert.ok(deployMigrations > verify && deployFunctions > deployMigrations);
  assert.match(workflow, /environment:\s+name: production/);
  assert.match(workflow, /apply_migrations:[\s\S]*?default: false/);
  assert.match(workflow, /deploy_edge_functions:[\s\S]*?default: false/);
  assert.match(workflow, /github\.event_name == 'workflow_dispatch' && inputs\.apply_migrations/);
  assert.match(workflow, /github\.event_name == 'workflow_dispatch' && inputs\.deploy_edge_functions/);
  assert.match(workflow, /supabase db push --dry-run --include-all --db-url/);
  assert.match(workflow, /SUPABASE_ACCESS_TOKEN: \$\{\{ secrets\.SUPABASE_ACCESS_TOKEN \}\}/);
  assert.match(workflow, /SUPABASE_PROJECT_ID: \$\{\{ secrets\.SUPABASE_PROJECT_ID \}\}/);
  assert.match(workflow, /SUPABASE_DB_PASSWORD: \$\{\{ secrets\.SUPABASE_DB_PASSWORD \}\}/);
});
