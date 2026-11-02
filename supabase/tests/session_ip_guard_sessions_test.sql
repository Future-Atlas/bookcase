begin;
select no_plan();

-- Old IP header based "security" check may be spoofed and must no longer be
-- directly callable from a signed-in browser.
select ok(not has_function_privilege('authenticated',
  'public.check_session_ip_change(inet,text)', 'EXECUTE'),
  'arbitrary client-supplied IP RPC is no longer executable');
select ok(not has_function_privilege('authenticated',
  'public.is_active_auth_session(uuid,uuid)', 'EXECUTE'),
  'signed-in browsers cannot enumerate live auth sessions');

-- Only server-side service_role can validate session existence. This test
-- runs locally inside a rolled-back transaction without any real user data.
insert into auth.users(id,aud,role,email,created_at,updated_at)
values ('7d000000-0000-4000-8000-000000000001','authenticated',
  'authenticated','session-test@example.test',now(),now());
insert into auth.users(id,aud,role,email,created_at,updated_at)
values ('7d000000-0000-4000-8000-000000000002','authenticated',
  'authenticated','session-other@example.test',now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at)
values ('7d000000-0000-4000-8000-000000000011',
  '7d000000-0000-4000-8000-000000000001',now(),now());
select is(public.is_active_auth_session(
  '7d000000-0000-4000-8000-000000000001',
  '7d000000-0000-4000-8000-000000000011'),true,
  'server validates a real GoTrue session belonging to the caller');
select is(public.is_active_auth_session(
  '7d000000-0000-4000-8000-000000000002',
  '7d000000-0000-4000-8000-000000000011'),false,
  'session cannot be used by another account');

update auth.sessions set not_after=now()-interval '1 minute'
where id='7d000000-0000-4000-8000-000000000011';
select is(public.is_active_auth_session(
  '7d000000-0000-4000-8000-000000000001',
  '7d000000-0000-4000-8000-000000000011'),false,
  'server rejects expired sessions');

select * from finish();
rollback;
