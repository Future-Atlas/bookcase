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

The 2026-10-29 production run applied and audited these migrations successfully:

- `20261028100000_restore_selected_account_to_free.sql`
- `20261028140000_add_optional_account_gender.sql`
- `20261029100000_harden_private_account_data_access.sql`

The later migration
`20261029143000_add_audited_private_data_controls.sql` must be tested in
staging and explicitly approved before production application. Until it is
applied, the administrative correction panel must be treated as unavailable.

## 3. Audited private-data corrections

- Ordinary users may change only phone number and optional gender after
  confirming their privacy password. They cannot directly update the private
  table, their legal name, or birth date.
- Operators use **Moderation > 個人情報対応** only for a verified inquiry,
  lawful disclosure request, or correction request.
- Every operator view requires an individual administrator account, the
  administrator's privacy password, a reason of at least ten characters, and
  an inquiry/case reference.
- Every correction records the actor, target, time, reason, reference, session
  identifier, and names of changed fields. The audit record deliberately does
  not copy name, birth date, phone number, gender, or email.
- Audit rows are append-only. Do not disable the immutability trigger during
  normal support work. Database-owner intervention is a break-glass action and
  must be recorded outside the affected database as an incident.
- Email is managed by the connected identity provider and Supabase Auth. The
  Sharemarium operator panel can view it for verified support but cannot change
  it.

## 4. Administrative access and MFA

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

## 5. Cloudflare WAF and rate limits

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

## 6. Backups and restore drills

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

## 7. Incident response

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

## 8. Safe security testing

- Use staging and dedicated test accounts for authorization tests.
- Automated checks may make low-rate, non-destructive requests only.
- Never run password guessing, load/DDoS tests, destructive SQL, data export,
  or third-party scanning against production without a written scope, limits,
  rollback plan, and explicit approval.
- Production verification should prefer catalog/privilege checks and a small
  number of known test-account requests.

## 9. Token response

- Access JWTs are short-lived, but a stolen refresh token or an active browser
  session can extend access.
- Keep Supabase refresh-token reuse detection enabled.
- On suspected theft, sign the user out globally/revoke the session and rotate
  any affected server secret. Changing only the access token is not enough.
- Never log authorization headers, OAuth callbacks, refresh tokens, or full
  request bodies containing credentials.


## Production security-only hotfix 2026-11-02

Main and develop diverged by 22 main-only and 47 develop-only commits. Security PR #225 selectively backports the fixes rather than overwriting main's existing TOTP and account recovery.

1. Apply DB migrations 20261102160000 and 20261102183000 after backing up. Verify private aggregates, revoked privileged RPCs, the avatar trigger, and service-only live-session RPC.
2. Deploy matching session-guard and admin-delete-account Supabase Edge Functions in the same release. IP headers from clients must not authorize any session action.
3. Deploy the main-branch production Cloudflare Worker and Flutter assets with API_RATE_LIMIT and CATALOG_RATE_LIMIT. This deployment is MANUAL: merging code is not sufficient.
4. Verify real sign-in, post review visibility, image placeholders, TOTP enrollment, account deletion authorization and the production hostname. Do not flood-test live APIs.
5. The real administrator must enroll a TOTP factor via Account Settings > 認証アプリ・二段階認証. After enrollment admin moderation requires AAL2. Administrative user deletion always requires AAL2; this assistant cannot enroll the user's authenticator.
6. In Cloudflare Dashboard check DDoS, WAF and custom-hostname per-IP API rate rules. Free-plan worker rate limits are approximate per location. A public *.workers.dev entry point may not receive custom-domain zone WAF protection; verify routing before disabling it.
7. Inspect hosted Supabase Auth password policies, session expiry, CAPTCHA, email verification and auth rate limits. Local config.toml is not proof of hosted settings. Leaked-password checking is a Pro-tier feature.
8. Weekly Dependabot and CodeQL are enabled. They do not replace regular audits and independent penetration testing. CSP currently includes unsafe-inline for Flutter/ad compatibility and requires a separate non-breaking remediation.

Security guarantees at the storage boundary: counts follow viewer visibility; new avatar_url writes require a Sharemarium-owned Supabase Storage bucket and the correct profile path. Historical external URLs are not bulk-deleted, but Flutter refuses to load them.
Production WAF status cannot be verified with the connected repository tools; do not mark that item complete without a dashboard check.
