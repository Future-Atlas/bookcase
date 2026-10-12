import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Keep production actions restricted to the canonical repository and branch.
// The staging project must never receive production migrations or Edge Functions.
const STAGING_PROJECT_REF = 'wpoigmywpewrrbudqhgh';

export function validateProductionEnvironment(env) {
  if (
    env.GITHUB_ACTIONS !== 'true' ||
    env.GITHUB_REPOSITORY !== 'Future-Atlas/sharemarium' ||
    env.GITHUB_REF !== 'refs/heads/main'
  ) {
    throw new Error('Supabase production preflight is restricted to main on Future-Atlas/sharemarium.');
  }

  const projectRef = env.SUPABASE_PROJECT_ID;
  if (typeof projectRef !== 'string' || !/^[a-z0-9]{20}$/.test(projectRef)) {
    throw new Error('SUPABASE_PROJECT_ID must be a valid 20-character Supabase project ref.');
  }
  if (projectRef === STAGING_PROJECT_REF) {
    throw new Error('SUPABASE_PROJECT_ID is the known staging project. Production deployment is blocked.');
  }

  const token = env.SUPABASE_ACCESS_TOKEN;
  if (
    typeof token !== 'string' ||
    token !== token.trim() ||
    !token.startsWith('sbp_') ||
    token.length <= 4
  ) {
    throw new Error('SUPABASE_ACCESS_TOKEN must be a Supabase Personal Access Token in the production environment secrets, without whitespace.');
  }

  const password = env.SUPABASE_DB_PASSWORD;
  if (typeof password !== 'string' || password.trim() === '') {
    throw new Error('SUPABASE_DB_PASSWORD is missing from the production environment secrets.');
  }
  return { projectRef, token };
}

/**
 * Read-only probe, before supabase link / db push / functions deploy.
 * Does not log the token, database password, Management API response or project name.
 * A 200 proves that the token can read this project, NOT that it can deploy changes.
 */
export async function preflightProductionSupabase({
  env = process.env,
  fetchImpl = globalThis.fetch,
} = {}) {
  const { projectRef, token } = validateProductionEnvironment(env);

  let response;
  try {
    response = await fetchImpl(
      `https://api.supabase.com/v1/projects/${projectRef}`,
      {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/json',
        },
        redirect: 'error',
        signal: AbortSignal.timeout(20000),
      },
    );
  } catch {
    throw new Error('Supabase Management API preflight failed to connect. No migrations or functions were deployed.');
  }

  if (response.status === 401) {
    throw new Error('Supabase production PAT was rejected (401). Check whether SUPABASE_ACCESS_TOKEN is expired, revoked or from the wrong account.');
  }
  if (response.status === 403) {
    throw new Error('Supabase production PAT cannot access this project (403). Check project membership and scoped PAT permissions.');
  }
  if (response.status === 404) {
    throw new Error('Supabase production project cannot be found (404). Verify SUPABASE_PROJECT_ID and PAT project access.');
  }
  if (!response.ok) {
    throw new Error('Supabase production Management API preflight did not succeed (HTTP ' + response.status + '). No deployment was attempted.');
  }

  let project;
  try {
    project = await response.json();
  } catch {
    throw new Error('Supabase production project preflight returned an unreadable response.');
  }
  // Supabase returns both an internal project ID and the public project ref.
  // The ref, not the internal ID, must match SUPABASE_PROJECT_ID.
  const returnedRef = project?.ref ?? project?.id;
  if (returnedRef !== projectRef) {
    throw new Error('Supabase production project ref did not match the response. Deployment is blocked.');
  }
  return true;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  try {
    await preflightProductionSupabase();
    process.stdout.write('Read-only Supabase production project access check passed. Migration and deploy permissions are verified separately.\n');
  } catch (error) {
    // Print a fixed, non-sensitive message. Never print raw HTTP bodies/headers.
    const message = error instanceof Error ? error.message : 'Unknown validation error';
    process.stderr.write(`::error::${message}\n`);
    process.exitCode = 1;
  }
}
