# featured_books production rollout

## Scope

Migration `20261013180000_add_featured_books.sql` is additive. It creates only:

- `public.featured_books`
- one ordering index
- row-level security policies for public reads and administrator writes
- grants and table/column comments

It does not update, delete, truncate, or rewrite any existing table or row. The
only reference to existing data is a nullable `created_by` foreign key to
`public.profiles(id)` with `ON DELETE SET NULL`.

## Before merging the PR

1. Replace the GitHub `production` environment secret
   `SUPABASE_ACCESS_TOKEN` with a valid token. Never paste the value in an
   issue, PR, log, or source file.
2. Add `SUPABASE_DB_URL` to the GitHub `production` environment. Use the
   production project's Supabase Session pooler URL on port `5432`. Replace the
   password placeholder locally and percent-encode special characters in the
   password before saving the secret.
3. Confirm `SUPABASE_PROJECT_ID`, `SUPABASE_DB_PASSWORD`, and the project ref in
   the Session pooler username all point to the same production project.
4. Wait for `Validate Supabase Migrations` on the PR. It starts a local
   Supabase instance, rebuilds the database from migrations, and runs the DB
   tests. It does not connect to production.
5. Review the migration and the `featured_books_test.sql` RLS coverage.

## After merging the PR

Merging to `main` runs `Deploy Database to Supabase` in plan-only mode. The
workflow validates the Session pooler host and port, reads remote migration
history, and runs `supabase db push --dry-run --include-all --db-url ...`, but
it does not apply migrations or deploy Edge Functions.

In the `Validate migration plan` log, confirm that
`20261013180000_add_featured_books.sql` is listed and that no unexpected
migration is pending.

## Apply after explicit approval

Only after the plan has been approved:

1. Open GitHub **Actions**.
2. Open **Deploy Database to Supabase**.
3. Select **Run workflow** on `main`.
4. Enable **Apply the validated migrations to the production database**.
5. Leave **Deploy production Edge Functions** disabled; `featured_books` does
   not require an Edge Function deployment.
6. Run the workflow and confirm both `Validate migration plan` and
   `Deploy database migrations` succeed.

## Verification

After the approved deployment:

1. Confirm `public.featured_books` exists in the Supabase Table Editor.
2. Confirm the table initially contains zero rows unless an administrator has
   deliberately curated a book.
3. Confirm an anonymous request can read an active row but cannot create,
   update, or delete rows.
4. Confirm a non-admin authenticated account cannot manage rows.
5. Confirm an allowlisted administrator can add, reorder, schedule, and remove
   featured books.

Do not manually create the table in the Supabase dashboard. The migration must
remain the authoritative record of the production schema.
