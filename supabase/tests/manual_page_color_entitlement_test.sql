begin;

select no_plan();

create or replace function test_manual_color_auth(test_uid uuid)
returns void
language plpgsql
as $$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', test_uid::text, true);
end;
$$;

insert into auth.users (id, aud, role, email, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values (
  '77000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'manual-color@example.test',
  now(),
  now(),
  '{}'::jsonb,
  '{}'::jsonb
);

insert into public.profiles (id, username, user_id, bio, is_private)
values (
  '77000000-0000-4000-8000-000000000001',
  'Manual Red',
  'manual_red',
  '',
  false
);

insert into private.page_color_manual_entitlements (
  profile_id, color_key, grant_reason
)
values (
  '77000000-0000-4000-8000-000000000001',
  'red',
  'test grant'
);

select test_manual_color_auth('77000000-0000-4000-8000-000000000001');

select ok(
  (public.current_user_page_color_access()->'unlocked_colors') ? 'red',
  'the manually granted red color is returned to the account'
);
select is(
  (public.current_user_page_color_access()->>'unlocks_remaining')::integer,
  0,
  'a manual color does not create or consume a post-milestone credit'
);
select is(
  (public.current_user_page_color_access()->>'next_milestone')::integer,
  10,
  'the first post milestone remains available after a manual grant'
);
select lives_ok(
  $$select public.update_profile_page_color('red')$$,
  'the account may select the manually granted red color'
);
select throws_ok(
  $$select public.update_profile_page_color('purple')$$,
  '42501',
  'page_color_access_required',
  'the manual red grant does not unlock another color'
);

reset role;

select is(
  (
    select count(*)::integer
    from private.page_color_manual_entitlements
    where profile_id = '77000000-0000-4000-8000-000000000001'::uuid
      and color_key = 'red'
  ),
  1,
  'the individual grant is stored once'
);

select * from finish();
rollback;
