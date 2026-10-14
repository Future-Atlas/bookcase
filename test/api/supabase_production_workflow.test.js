import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflow = fs.readFileSync(
  '.github/workflows/supabase-deploy.yaml',
  'utf8',
);

test('production Supabase workflow uses the IPv4 Session pooler URL', () => {
  assert.match(workflow, /SUPABASE_DB_URL: \$\{\{ secrets\.SUPABASE_DB_URL \}\}/);
  assert.match(workflow, /parsed\.port !== '5432'/);
  assert.match(workflow, /\.pooler\.supabase\.com/);
  assert.match(
    workflow,
    /supabase migration list --db-url "\$SUPABASE_DB_URL"/,
  );
  assert.match(
    workflow,
    /supabase db push --dry-run --include-all --db-url "\$SUPABASE_DB_URL"/,
  );
  assert.match(
    workflow,
    /supabase db push --include-all --db-url "\$SUPABASE_DB_URL"/,
  );
});

test('production database and Edge Function changes require manual opt-in', () => {
  assert.match(workflow, /apply_migrations:[\s\S]*?default: false/);
  assert.match(workflow, /deploy_edge_functions:[\s\S]*?default: false/);
  assert.match(
    workflow,
    /github\.event_name == 'workflow_dispatch' && inputs\.apply_migrations/,
  );
  assert.match(
    workflow,
    /github\.event_name == 'workflow_dispatch' && inputs\.deploy_edge_functions/,
  );
});

test('database URL is never echoed by the workflow', () => {
  assert.doesNotMatch(workflow, /echo[^\n]*SUPABASE_DB_URL/);
  assert.doesNotMatch(workflow, /print[^\n]*SUPABASE_DB_URL/);
});
