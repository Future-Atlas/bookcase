# Sharemarium security operations

Last reviewed: 2026-10-29

This runbook covers the operational controls that cannot be guaranteed by
application code alone. It must be reviewed after authentication, hosting, or
personal-data collection changes.

## 1. Personal-data boundary

- Public profile data belongs in `public.profiles` only.
- Legal name, birth date, phone number, and optional gender belong in
  `public.account_details`. Browser access is owner-only through RLS.
- Email addresses remain in Supabase Auth because they are authentication and
  contact identifiers. They must not be copied into public profile rows.
- Privacy-password hashes are never selected directly by browser roles.
- Contact requests are write-only to browser roles.
- Service-role or Supabase secret keys are server-side only. They must never be
  placed in Flutter `--dart-define`, `web/`, a public API response, a URL, or a
  browser log.

The strongest protection is data minimization. Before public registration is
expanded, confirm that mandatory legal name, date of birth, and phone number
are all operationally necessary. Make unnecessary fields optional or stop
collecting them.

## 2. Production migration and RLS release gate

1. Apply migrations to staging.
2. Run `supabase test db`, including
   `private_account_data_rls_test.sql` and `rls_policies_test.sql`.
3. Test with two staging users:
   - user A can read/update only A's `account_details` row;
   - user A cannot read or update B's row;
   - anonymous requests cannot read `account_details`;
   - neither browser role can read contact messages or password hashes;
   - private posts, shelves, and favorites are hidden from the other user;
   - deleted-account retention is inaccessible to browser roles.
4. Review the production dry-run output and obtain explicit approval.
5. Manually run **Deploy Database to Supabase** with
   `apply_migrations=true` and `deploy_edge_functions=false`, unless an Edge
   Function change is separately approved.
6. Manually run **Audit Production Security Boundaries**. The workflow uses a
   read-only transaction, reads catalog metadata only, and never selects PII.

As of the 2026-10-28 dry run, production still had these pending migrations:

- `20261028100000_restore_selected_account_to_free.sql`
- `20261028140000_add_optional_account_gender.sql`

The security migration `20261029100000_harden_private_account_data_access.sql`
must also be present before the production audit can pass.

## 3. Administrative access and MFA

- GitHub: require 2FA for every organization member; use passkeys or security
  keys where possible. Keep branch protection and CodeQL required on `main`.
- Cloudflare: require MFA, remove unused members/tokens, and scope deployment
  tokens to the single account/zone and Workers permission needed.
- Supabase: require MFA for operators, remove unused organization members, and
  assign the least privileged project role available.
- Do not share administrator accounts. Each operator uses an individual
  account so audit history remains attributable.
- Review access quarterly and immediately after a collaborator leaves.

For highly sensitive in-app operator actions, add Supabase MFA and require an
`aal2` session in the API/database policy. Dashboard-account MFA and in-app MFA
are separate controls.

## 4. Cloudflare WAF and rate limits

In the Cloudflare dashboard for `sharemarium.com`:

1. Open **Security** > **Security rules**.
2. Confirm the Cloudflare Free Managed Ruleset is active.
3. Create rate-limit rules initially in Log/Managed Challenge mode and review
   normal traffic before switching to Block.
4. Suggested starting points per source IP:
   - `/api/rakuten`: 60 requests per minute;
   - other `/api/*`: 120 requests per minute;
   - repeated error-heavy traffic: Managed Challenge rather than a permanent
     block.
5. Keep the database contact-request limit of five per rolling 24 hours. It is
   account-based while signed in and normalized-email-based while signed out.

Do not rate-limit Flutter static assets with the same threshold as APIs.

## 5. Backups and restore drills

- Paid Supabase projects: confirm daily backups under **Database > Backups**.
  Consider PITR when the cost is justified.
- Free projects: take regular logical exports and encrypt them before storing
  them outside the development PC. A raw dump contains personal information
  and must not be uploaded as a normal GitHub artifact or committed to Git.
- At least quarterly, restore the newest backup into a separate test project.
- Verify table counts and a small set of non-sensitive integrity checks, then
  delete the temporary restore after the drill.
- Record the backup timestamp, restore duration, result, and operator. A backup
  that has never been restored is not a verified recovery plan.

## 6. Incident response

1. Contain: disable the affected key, session, endpoint, or deployment.
2. Preserve evidence: note time, affected account/project, relevant request IDs,
   and configuration changes without copying tokens or PII into tickets.
3. Rotate: Supabase secret/access tokens, database password, Cloudflare token,
   GitHub token, and OAuth secrets according to the affected boundary.
4. Scope: use audit logs and database metadata to identify affected data and
   time range.
5. Recover: deploy the fix, invalidate affected sessions, and restore only when
   integrity is in doubt.
6. Notify: determine legal/user notification duties promptly with qualified
   counsel. Do not delay the assessment while waiting for perfect certainty.
7. Review: document the root cause and add a regression test.

Primary incident owner: service operator. A second named person should be
designated before public registration grows so containment does not depend on
one unavailable account holder.

## 7. Safe security testing

- Use staging and dedicated test accounts for authorization tests.
- Automated checks may make low-rate, non-destructive requests only.
- Never run password guessing, load/DDoS tests, destructive SQL, data export,
  or third-party scanning against production without a written scope, limits,
  rollback plan, and explicit approval.
- Production verification should prefer catalog/privilege checks and a small
  number of known test-account requests.

## 8. Token response

- Access JWTs are short-lived, but a stolen refresh token or an active browser
  session can extend access.
- Keep Supabase refresh-token reuse detection enabled.
- On suspected theft, sign the user out globally/revoke the session and rotate
  any affected server secret. Changing only the access token is not enough.
- Never log authorization headers, OAuth callbacks, refresh tokens, or full
  request bodies containing credentials.
