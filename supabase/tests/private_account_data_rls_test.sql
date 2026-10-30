begin;

select no_plan();

create or replace function test_private_auth(test_role text, test_uid uuid default null)
returns void
language plpgsql
as $$
begin
  execute format('set local role %I', test_role);
  perform set_config('request.jwt.claim.role', test_role, true);
  perform set_config('request.jwt.claim.sub', coalesce(test_uid::text, ''), true);
end;
$$;

select ok(
  (select relrowsecurity from pg_class where oid = 'public.account_details'::regclass),
  'account_details has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.legal_consents'::regclass),
  'legal_consents has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.contact_requests'::regclass),
  'contact_requests has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.privacy_password_credentials'::regclass),
  'privacy password credentials has RLS enabled'
);

select ok(
  not has_table_privilege('anon', 'public.account_details', 'SELECT'),
  'anonymous role has no account_details read grant'
);
select ok(
  not has_table_privilege('authenticated', 'public.contact_requests', 'SELECT'),
  'authenticated role cannot read contact requests'
);
select ok(
  not has_table_privilege('authenticated', 'public.privacy_password_credentials', 'SELECT'),
  'authenticated role cannot read privacy password hashes'
);

insert into auth.users (id, aud, role, email, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('29000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'private-owner-a@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('29000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'private-owner-b@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb);

insert into public.profiles (id, username, user_id, bio, is_private)
values
  ('29000000-0000-4000-8000-000000000001', 'Private A', 'private_a', '', false),
  ('29000000-0000-4000-8000-000000000002', 'Private B', 'private_b', '', false);

insert into public.account_details (
  profile_id, full_name, family_name, given_name, gender, birth_date, phone_number
)
values
  ('29000000-0000-4000-8000-000000000001', 'Test A', 'Test', 'A', 'undisclosed', date '2000-01-01', '+810000000001'),
  ('29000000-0000-4000-8000-000000000002', 'Test B', 'Test', 'B', 'undisclosed', date '2000-01-02', '+810000000002');

insert into public.privacy_password_credentials (profile_id, password_hash)
values
  (
    '29000000-0000-4000-8000-000000000001',
    extensions.crypt('AdminPass123', extensions.gen_salt('bf', 4))
  ),
  (
    '29000000-0000-4000-8000-000000000002',
    extensions.crypt('OwnerPass123', extensions.gen_salt('bf', 4))
  );

insert into public.app_admins (profile_id)
values ('29000000-0000-4000-8000-000000000001');

select test_private_auth('anon');
select throws_ok(
  $$select profile_id from public.account_details limit 1$$,
  '42501',
  'permission denied for table account_details',
  'anonymous requests cannot read registration data'
);

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_private_auth('authenticated', '29000000-0000-4000-8000-000000000002');

select results_eq(
  $$select profile_id from public.account_details order by profile_id$$,
  $$values ('29000000-0000-4000-8000-000000000002'::uuid)$$,
  'a signed-in user sees only their own registration row'
);
select throws_ok(
  $$update public.account_details
    set phone_number = '+819999999999'
    where profile_id = '29000000-0000-4000-8000-000000000002'$$,
  '42501',
  'permission denied for table account_details',
  'authenticated users have no direct update grant for registration data'
);
select lives_ok(
  $$select public.update_own_private_contact_details(
      'OwnerPass123', 'female', '+810000000009'
    )$$,
  'the owner can update only phone number and gender through the password RPC'
);
select results_eq(
  $$select family_name, given_name, birth_date, phone_number, gender
    from public.account_details
    where profile_id = '29000000-0000-4000-8000-000000000002'$$,
  $$values ('Test'::text, 'B'::text, date '2000-01-02', '+810000000009'::text, 'female'::text)$$,
  'the owner RPC leaves name and birth date unchanged'
);
select throws_ok(
  $$select public.admin_read_private_account_details(
      'private_a', 'OwnerPass123',
      'Unauthorized support access', 'REQ-NONADMIN'
    )$$,
  '42501',
  'Administrator access required',
  'a non-admin cannot use the private-data operator function'
);
select throws_ok(
  $$select profile_id from public.privacy_password_credentials limit 1$$,
  '42501',
  'permission denied for table privacy_password_credentials',
  'password hashes are not directly readable by authenticated users'
);
select throws_ok(
  $$select id from public.contact_requests limit 1$$,
  '42501',
  'permission denied for table contact_requests',
  'contact messages are not directly readable by authenticated users'
);

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_private_auth('authenticated', '29000000-0000-4000-8000-000000000001');

select lives_ok(
  $$select public.admin_read_private_account_details(
      'private_b', 'AdminPass123',
      'Verified user correction request', 'REQ-PRIVATE-001'
    )$$,
  'an authorized admin can read private data after additional verification'
);
select results_eq(
  $$select public.admin_update_private_account_details(
      'private_b', 'AdminPass123',
      'Verified user correction request', 'REQ-PRIVATE-001',
      'Corrected', 'Person', date '2001-02-03', '+810000000022', 'male'
    )$$,
  $$values (array['family_name','given_name','birth_date','phone_number','gender']::text[])$$,
  'an authorized admin can correct private data and receives changed field names'
);

reset role;
select results_eq(
  $$select action, request_reference, changed_fields
    from public.private_data_admin_audit
    order by id$$,
  $$values
      ('view'::text, 'REQ-PRIVATE-001'::text, array[]::text[]),
      ('update'::text, 'REQ-PRIVATE-001'::text,
        array['family_name','given_name','birth_date','phone_number','gender']::text[])$$,
  'view and update actions create append-only audit evidence without copied values'
);
select is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'private_data_admin_audit'
      and column_name in (
        'family_name', 'given_name', 'birth_date', 'phone_number', 'gender', 'email'
      )
  ),
  0,
  'the audit table has no columns that duplicate private values'
);
select throws_ok(
  $$update public.private_data_admin_audit set reason = 'tampered reason'$$,
  '42501',
  'Private-data audit records are append-only',
  'audit evidence cannot be updated'
);
select throws_ok(
  $$delete from public.private_data_admin_audit$$,
  '42501',
  'Private-data audit records are append-only',
  'audit evidence cannot be deleted'
);

select * from finish();
rollback;
