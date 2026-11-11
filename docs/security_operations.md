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

### Verified in code (2026-11-02, PR security hardening)

- Cloudflare Worker uses two native rate-limit bindings with independent
  namespaces for default, staging, and production:
  - `API_RATE_LIMIT`: 120 requests per 60 seconds per Cloudflare location
    and connecting IP for API routes, sitemap, and dynamic bot/SEO rendering.
  - `CATALOG_RATE_LIMIT`: 24 requests per 60 seconds for the shared
    NDL/Open Library/openBD catalog proxy group, in addition to the general
    API quota. Static Flutter assets do **not** consume API quotas.
- Quota checks happen before the API handler contacts any third party;
  blocked requests return 429, `Retry-After: 60`, and `Cache-Control:
  no-store`. Missing or failing bindings cause 503 (fail-closed), protecting
  free-tier upstream quotas rather than silently bypassing the check.
- No user IPs are logged or stored by Sharemarium's code. The only identity
  used is Cloudflare's trusted `cf-connecting-ip`; do not use spoofable
  `x-forwarded-for` headers for quota keys.
- Cloudflare's Worker Rate Limiting API is **approximate and per Cloudflare
  edge location**. It is not a strict globally synchronized limit. Shared
  home/work/campus NATs also share a per-IP allowance. Tune thresholds using
  normal traffic data before moving to account-based quotas.
- The existing catalog cache and in-flight coalescing and the Rakuten
  Durable Object quota remain independent layers. No new Supabase tables or
  permanent catalog storage are created by the quota bindings.

### Dashboard action still required (NOT verifiable from GitHub)

For the proxied custom domain `sharemarium.com`:

1. Open Cloudflare **Security > Security rules**, verify the available
   Free Managed Ruleset/WAF protection is enabled.
2. Add a Free-plan rate limiting rule for `/api/*` using the expression
   `starts_with(http.request.uri.path, "/api/")`. The Free plan's rule
   action is **Block**, with a 10-second period; start with a conservative
   threshold based on observed legitimate traffic, review events and tune
   down only if abuse is observed. Do not apply this rule to `/assets/*`.
3. Validate in Security Events that the rule is matching the **proxied
   custom hostname** and is not blocking ordinary users. Test using
   approved low-rate validation; never run synthetic DoS traffic.
4. Workers served by their `*.workers.dev` hostname are not necessarily
   covered by the custom-domain zone WAF. The current Wrangler config
   still has `workers_dev: true` even for production. Once the production
   custom domain and rollbacks are verified, disable that alternate public
   endpoint (a separate reviewed production configuration change).
5. For direct Supabase Auth/REST/Edge Functions requests, Cloudflare zone
   rules do not automatically apply. Keep Supabase Auth rate limits,
   session checking, RLS, JWT verification, and sensitive RPC protections.

**Important:** GitHub contains operational instructions; it does not grant
this assistant access to a Cloudflare-zone dashboard. Do **not** mark WAF
activation complete until the dashboard is checked.

Worker Rate Limiting API:
https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/

Free WAF rule parameters:
https://developers.cloudflare.com/waf/rate-limiting-rules/

## 5a. Supabase production security advisor follow-up (2026-11-02)

A **read-only** remote review on 2026-11-02 found that all 26 public
production tables have RLS enabled, including account and contact tables.
There are still Security Advisor warnings; RLS status alone is not a full
security audit:

- 51 `anon_security_definer_function_executable` findings (anonymous RPC
  grants, including admin/moderation endpoints); many functions check
  `auth.uid()` or `is_current_user_admin()` internally, so a finding is
  **not proof of exploitability**.
- 72 `authenticated_security_definer_function_executable` findings. Many
  authenticated entrypoints intentionally use privileged functions with
  owner / administrator checks. Review their bodies individually rather than
  blindly removing `authenticated` grants.
- 3 `function_search_path_mutable` warnings on internal private
  name/email/phone normalizers.
- `auth_leaked_password_protection` warning: compromised-password checks
  are not enabled. Enable after checking plan availability in Supabase Auth
  password-security settings.
- 7 `rls_enabled_no_policy` INFO findings on intentionally inaccessible
  private/admin/audit tables; verify they remain inaccessible to browser
  roles instead of adding overly permissive RLS policies to silence lints.

The follow-up migration
`20261102160000_restrict_anonymous_privileged_rpcs.sql` removes unnecessary
anonymous `EXECUTE` privileges from **21** admin or authenticated-only RPC
signatures, while retaining their required `authenticated` and
`service_role` access and preserving public RLS helpers. It also pins the
three private normalizers' `search_path`. Verify in staging first with the
pgTAP tests `anonymous_privileged_rpcs_test.sql`, then re-run Supabase
Security Advisor in both environments. Do not infer that all advisor warnings
will disappear: remaining helper or authenticated-only definer functions
require separate review.

Production database remains **unchanged** until staged validation and an
explicit production migration approval. Cloudflare WAF settings are another
separate, dashboard-only action (see section 5).

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
3. Deploy the main-branch production Cloudflare Worker and Flutter assets with API_RATE_LIMIT and CATALOG_RATE_LIMIT. WARNING: CI on a main push **automatically** calls deploy-cloudflare-production.yaml after its Flutter job succeeds. Therefore finish the DB migrations and matching Edge Function deployments BEFORE merging this PR, or explicitly gate the CI deployment. The workflow also exposes a separate manual DEPLOY option.
4. Verify real sign-in, post review visibility, image placeholders, TOTP enrollment, account deletion authorization and the production hostname. Do not flood-test live APIs.
5. The real administrator must enroll a TOTP factor via Account Settings > 認証アプリ・二段階認証. After enrollment admin moderation requires AAL2. Administrative user deletion always requires AAL2; this assistant cannot enroll the user's authenticator.
6. In Cloudflare Dashboard check DDoS, WAF and custom-hostname per-IP API rate rules. Free-plan worker rate limits are approximate per location. A public *.workers.dev entry point may not receive custom-domain zone WAF protection; verify routing before disabling it.
7. Inspect hosted Supabase Auth password policies, session expiry, CAPTCHA, email verification and auth rate limits. Local config.toml is not proof of hosted settings. Leaked-password checking is a Pro-tier feature.
8. Weekly Dependabot and CodeQL are enabled. They do not replace regular audits and independent penetration testing. CSP currently includes unsafe-inline for Flutter/ad compatibility and requires a separate non-breaking remediation.

Security guarantees at the storage boundary: counts follow viewer visibility; new avatar_url writes require a Sharemarium-owned Supabase Storage bucket and the correct profile path. Historical external URLs are not bulk-deleted, but Flutter refuses to load them.
Production WAF status cannot be verified with the connected repository tools; do not mark that item complete without a dashboard check.
