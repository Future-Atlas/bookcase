begin;
select no_plan();

-- Only a service-role Edge Function may check verified GoTrue sessions.
select ok(not has_function_privilege('anon',
    'public.check_session_ip_change(inet,text)', 'EXECUTE'),
  'old user-supplied IP RPC is inaccessible to anon');
select ok(not has_function_privilege('authenticated',
    'public.check_session_ip_change(inet,text)', 'EXECUTE'),
  'old user-supplied IP RPC is inaccessible to authenticated callers');
select ok(not has_function_privilege('anon',
    'public.is_active_auth_session(uuid,uuid)', 'EXECUTE'),
  'anonymous users cannot probe authentication sessions');
select ok(not has_function_privilege('authenticated',
    'public.is_active_auth_session(uuid,uuid)', 'EXECUTE'),
  'authenticated users cannot probe authentication sessions');
select ok(has_function_privilege('service_role',
    'public.is_active_auth_session(uuid,uuid)', 'EXECUTE'),
  'Edge Function service-role may validate authenticated sessions');
select is(public.is_active_auth_session(
    '00000000-0000-4000-8000-000000006901',
    '00000000-0000-4000-8000-000000006909'), false,
  'unknown session is not accepted');

-- A private reader's review must not change publicly visible book counters.
insert into auth.users
  (id,aud,role,email,created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
values
  ('00000000-0000-4000-8000-000000006901','authenticated',
   'authenticated','security-public@example.test',now(),now(),'{}','{}'),
  ('00000000-0000-4000-8000-000000006902','authenticated',
   'authenticated','security-private@example.test',now(),now(),'{}','{}');
insert into public.profiles (id,username,user_id,is_private,avatar_url)
values
  ('00000000-0000-4000-8000-000000006901','Security Public','sec_public',false,
   'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/00000000-0000-4000-8000-000000006901/avatar.webp?v=123'),
  ('00000000-0000-4000-8000-000000006902','Security Private','sec_private',true,null);
insert into public.posts
 (id,profile_id,book_id,rating,comment,book_title,book_author)
values
 ('20000000-0000-4000-8000-000000006901',
  '00000000-0000-4000-8000-000000006901',
  'security-same-book',4,'public review','Review','Author'),
 ('20000000-0000-4000-8000-000000006902',
  '00000000-0000-4000-8000-000000006902',
  'security-same-book',4,'private review','Review','Author');

select set_config('request.jwt.claim.role','anon',true);
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select is(
  (select read_count from public.get_book_engagement_counts('security-same-book')),
  1::bigint, 'anonymous aggregate hides private reviews');
reset role;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006902',true);
set local role authenticated;
select is(
  (select read_count from public.get_book_engagement_counts('security-same-book')),
  2::bigint, 'owner can count own private review as visible');

-- A user can update only their own approved avatar URL.
select throws_ok(
  $$update public.profiles set avatar_url='https://tracker.example/pixel.png'
       where id='00000000-0000-4000-8000-000000006902'::uuid$$,
  '23514','avatar_url_source_not_allowed',
  'remote tracking images rejected at the database layer');
select throws_ok(
  $$update public.profiles set avatar_url=
       'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/00000000-0000-4000-8000-000000006901/avatar.jpg'
       where id='00000000-0000-4000-8000-000000006902'::uuid$$,
  '23514','avatar_url_source_not_allowed',
  'profile cannot set another owner avatar path');
select lives_ok(
  $$update public.profiles set avatar_url=
       'https://wpoigmywpewrrbudqhgh.supabase.co/storage/v1/object/public/avatars/00000000-0000-4000-8000-000000006902/avatar.png?v=12345'
       where id='00000000-0000-4000-8000-000000006902'::uuid$$,
  'own approved Supabase Storage avatar with version marker is accepted');
select lives_ok(
  $$update public.profiles set avatar_url='' where
       id='00000000-0000-4000-8000-000000006902'::uuid$$,
  'owner can remove avatar');
reset role;

select * from finish();
rollback;
