# GitHub branch protection and required checks

Sharemarium uses `develop` as the long-lived staging/integration branch and
`main` as the production release branch.

## Current repository state (verified 2026-10-12)

A repository-level GitHub ruleset is **active**:

- Ruleset: [protect branch](https://github.com/Future-Atlas/sharemarium/rules/24911692) (ID `24911692`).
- Conditions: default branch (`develop`) and `refs/heads/main`.
- Required: pull request before merging, required status check context `flutter`
  from the GitHub Actions integration, strict check freshness, no branch
  deletion, no non-fast-forward push.
- Bypass actors: none (`current_user_can_bypass: never`).
- **Required approval count: 0**. This does **not** enforce the intended
  independent human review. Change the rule to 1 approval when a qualified
  reviewer is available and decide how emergencies are handled.
- The legacy branch-protection API can show `protection.enabled=false`
  even while branch `protected=true` because protection is supplied by an
  active ruleset, not by a legacy branch-protection rule.

Do not mark the Asana branch-protection task fully complete until the human
review requirement, failing-check rejection behavior and documentation have
been verified in the actual GitHub UI.

## Required target policy for `main`

Configure a ruleset or branch-protection rule for `main` that:

- requires a pull request before merging
- requires status checks to pass before merging
- requires `CI / flutter`
- prevents ordinary direct pushes to `main`
- does not allow a failing/stale required check to be bypassed accidentally
- should require at least one independent human approval once review coverage exists (currently **not enforced**)
- documents any administrator/bypass actors explicitly

For changes under `supabase/**` or `.github/workflows/supabase-*.yaml`, also
require the Supabase validation check when GitHub allows a path-specific check to
be made required without blocking unrelated PRs.

## Recommended policy for `develop`

`develop` is the staging/integration branch. Use the same PR + CI model where
practical:

- feature/fix branches merge into `develop` through PRs
- `CI / flutter` must pass before merge
- database-related changes must pass Supabase validation
- direct pushes are currently restricted through the active repository ruleset

The production release path remains:

```text
feature/* -> develop -> release PR -> main
```

## What the checks actually run

`.github/workflows/ci.yaml` runs:

- `flutter analyze --no-fatal-infos --no-fatal-warnings`
- `flutter test`
- `flutter build web --release`
- `npm ci`
- `npm run test:api`
- Deno type checks for billing/account-deletion Edge Functions
- Flutter dependency lockfile reproducibility check

The required check name is the workflow/job combination `CI / flutter`.

`.github/workflows/supabase-validate.yaml` runs for relevant pull requests and
uses Supabase CLI 2.115.0 to:

- start local Supabase services
- replay migrations with `supabase db reset`
- execute pgTAP/RLS tests with `supabase test db`

Its workflow/job combination is `Validate Supabase Migrations / validate`.

## Deployment environments

Deployment credentials are intentionally separated through GitHub Environments:

- `production`: production Vercel and Supabase credentials
- `staging`: staging Vercel and Supabase credentials

Web deployment workflows:

- `.github/workflows/deploy.yaml`
- `.github/workflows/deploy-staging.yaml`

Database/Edge Function deployment workflows:

- `.github/workflows/supabase-deploy.yaml`
- `.github/workflows/supabase-deploy-staging.yaml`

Do not move environment-specific credentials into shared repository-level values
when that would allow staging and production targets to be confused.

## Completion check for the Asana task

Before marking branch protection complete, verify in GitHub that:

1. `main` is protected by the intended ruleset/branch rule.
2. A PR with failing `CI / flutter` cannot be merged through the normal path.
3. Ordinary contributors cannot push directly to `main`.
4. Database-related PRs run the Supabase validation workflow.
5. An independent human approval requirement is enabled or its temporary absence is documented and accepted.
6. This document still matches the actual settings.
