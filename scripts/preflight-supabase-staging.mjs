import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { STAGING_PROJECT, validateEnvironment } from './deploy-staging-db.mjs';

/**
 * Management API GET is read only. Confirm that the GitHub staging PAT can
 * access the approved staging project before supabase link/db push/function
 * deploy. Never print a token, password, response body, or project metadata.
 */
export async function preflightStagingSupabase({
  env = process.env,
  fetchImpl = globalThis.fetch,
} = {}) {
  validateEnvironment(env);

  const token = env.SUPABASE_ACCESS_TOKEN;
  let response;
  try {
    response = await fetchImpl('https://api.supabase.com/v1/projects/' + STAGING_PROJECT, {
      method: 'GET',
      headers: {
        Authorization: 'Bearer ' + token,
        Accept: 'application/json',
      },
      redirect: 'error',
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    throw new Error('Staging Supabase read-only preflight could not connect. No changes were attempted.');
  }

  if (response.status === 401) {
    throw new Error('Staging Supabase PAT rejected (401). Check that the staging access token is valid and not revoked.');
  }
  if (response.status === 403) {
    throw new Error('Staging Supabase PAT lacks project access (403). Check project membership and permissions.');
  }
  if (response.status === 404) {
    throw new Error('Staging Supabase project was not found (404). Verify project access and environment mapping.');
  }
  if (!response.ok) {
    throw new Error('Staging Supabase read-only preflight failed with HTTP ' + response.status + '. No changes were attempted.');
  }

  let project;
  try {
    project = await response.json();
  } catch {
    throw new Error('Staging Supabase read-only preflight returned an unreadable response.');
  }
  if ((project?.ref ?? project?.id) !== STAGING_PROJECT) {
    throw new Error('Staging Supabase project reference mismatch. Deployment blocked.');
  }
  return true;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    await preflightStagingSupabase();
    process.stdout.write('Staging Supabase read-only PAT/project verification passed. Deployment privileges remain unverified.\n');
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Staging Supabase preflight failed';
    process.stderr.write('::error::' + message + '\n');
    process.exitCode = 1;
  }
}
