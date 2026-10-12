begin;
select plan(5);
insert into auth.users(id, aud, role, email, created_at, updated_at)
values ('7d000000-0000-4000-8000-000000000001','authenticated','authenticated','session-test@example.test',now(),now());
insert into public.profiles(id,username,user_id)
values ('7d000000-0000-4000-8000-000000000001','Session test','session_test');
set local role authenticated;
select set_config('request.jwt.claim.sub','7d000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"7d000000-0000-4000-8000-000000000001","session_id":"7d000000-0000-4000-8000-000000000011"}',true);
select is((select ip_changed from public.check_session_ip_change('192.0.2.1')),false,'first login accepted');
select is((select ip_changed from public.check_session_ip_change('192.0.2.1')),false,'same session IP accepted');
select set_config('request.jwt.claims','{"sub":"7d000000-0000-4000-8000-000000000001","session_id":"7d000000-0000-4000-8000-000000000012"}',true);
select is((select ip_changed from public.check_session_ip_change('198.51.100.1')),false,'independent fresh login from different network accepted');
select is((select ip_changed from public.check_session_ip_change('198.51.100.2')),true,'same session changing IP rejected');
select is((select ip_changed from public.check_session_ip_change('198.51.100.1')),true,'flagged session remains rejected even on original IP');
select * from finish();
rollback;
