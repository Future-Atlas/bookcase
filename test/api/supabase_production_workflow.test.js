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
  assert.match(workflow, /parsed\.username !== 'postgres\.'/);
  assert.match(workflow, /\.pooler\.supabase\.com/);
  assert.match(
    workflow,
    /supabase migration list --remote="\$SUPABASE_DB_URL"/,
  );
  assert.match(
    workflow,
    /supabase db push --dry-run --include-all --remote="\$SUPABASE_DB_URL"/,
  );
  assert.match(
    workflow,
    /supabase db push --include-all --yes --remote="\$SUPABASE_DB_URL"/,
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

test('CLI v3 production commands always choose an explicit remote and require manual consent', () => {
  assert.match(workflow, /version: "3\.0\.0"/);
  assert.match(workflow, /supabase db push --include-all --yes --remote=/);
  assert.match(workflow, /supabase functions deploy "\$function_name" --remote=/);
  assert.match(workflow, /supabase functions deploy "\$function_name" --remote="\$SUPABASE_PROJECT_ID" --yes/);
  assert.doesNotMatch(workflow, /supabase db push --include-all --db-url/);
});

test('database URL is never echoed by the workflow', () => {
  assert.doesNotMatch(workflow, /echo[^\n]*SUPABASE_DB_URL/);
  assert.doesNotMatch(workflow, /print[^\n]*SUPABASE_DB_URL/);
});
