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
select test_private_auth('authenticated', '29000000-0000-4000-8000-000000000001');

select results_eq(
  $$select profile_id from public.account_details order by profile_id$$,
  $$values ('29000000-0000-4000-8000-000000000001'::uuid)$$,
  'a signed-in user sees only their own registration row'
);
select results_eq(
  $$with changed as (
      update public.account_details
      set phone_number = '+819999999999'
      where profile_id = '29000000-0000-4000-8000-000000000002'
      returning 1
    ) select count(*)::bigint from changed$$,
  $$values (0::bigint)$$,
  'a signed-in user cannot update another registration row'
);
select lives_ok(
  $$update public.account_details
    set phone_number = '+810000000009'
    where profile_id = '29000000-0000-4000-8000-000000000001'$$,
  'the owner can update their own registration row'
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
select * from finish();
rollback;
