begin;

select no_plan();

create or replace function test_auth(test_role text, test_uid uuid default null)
returns void
language plpgsql
as $$
begin
  execute format('set local role %I', test_role);
  perform set_config('request.jwt.claim.role', test_role, true);
  perform set_config('request.jwt.claim.sub', coalesce(test_uid::text, ''), true);
end;
$$;

select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'profiles has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.posts'::regclass), 'posts has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.favorites'::regclass), 'favorites has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.post_replies'::regclass), 'post_replies has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), 'notifications has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.blocks'::regclass), 'blocks has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.moderation_reports'::regclass), 'moderation_reports has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.app_admins'::regclass), 'app_admins has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.adult_content_terms'::regclass), 'adult_content_terms has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.privacy_password_credentials'::regclass), 'privacy password credentials has row level security enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.privacy_password_recovery_requests'::regclass), 'privacy password recovery requests has row level security enabled');

select ok(exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'Allow public read access for profiles'), 'guest profile read policy exists');
select ok(exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'posts' and policyname = 'Allow visible profile posts to be read'), 'visible post read policy exists');
select ok(exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'posts' and policyname = 'Allow authenticated users to insert posts'), 'authenticated post insert policy exists');
select ok(exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'favorites' and policyname = 'Allow authenticated users to insert/delete favorites'), 'authenticated favorite policy exists');

insert into auth.users (id, aud, role, email, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-4000-8000-000000000101', 'authenticated', 'authenticated', 'rls-owner@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000000102', 'authenticated', 'authenticated', 'rls-other@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000000103', 'authenticated', 'authenticated', 'rls-private@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000000104', 'authenticated', 'authenticated', 'rls-admin@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000000105', 'authenticated', 'authenticated', 'rls-blocked@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb);

insert into public.profiles (id, username, user_id, bio, is_private, page_color)
values
  ('00000000-0000-4000-8000-000000000101', 'RLS Owner', 'rls_owner', 'public owner', false, 'yellow'),
  ('00000000-0000-4000-8000-000000000102', 'RLS Other', 'rls_other', 'public other', false, 'blue'),
  ('00000000-0000-4000-8000-000000000103', 'RLS Private', 'rls_private', 'private owner', true, 'green'),
  ('00000000-0000-4000-8000-000000000104', 'RLS Admin', 'rls_admin', 'admin owner', false, 'yellow'),
  ('00000000-0000-4000-8000-000000000105', 'RLS Blocked', 'rls_blocked', 'blocked owner', false, 'green');

insert into public.app_admins (profile_id) values ('00000000-0000-4000-8000-000000000104');

insert into private.reply_entitlements (profile_id, can_reply, granted_at)
values
  ('00000000-0000-4000-8000-000000000101', true, now()),
  ('00000000-0000-4000-8000-000000000102', true, now()),
  ('00000000-0000-4000-8000-000000000103', true, now()),
  ('00000000-0000-4000-8000-000000000104', false, null);

insert into public.posts (id, profile_id, book_id, rating, comment, book_title, book_author)
values
  ('10000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000101', 'rls-public-book', 4, 'public post', 'RLS Public Book', 'Test Author'),
  ('10000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000101', 'rls-owner-delete-book', 4, 'deletable post', 'RLS Deletable Book', 'Test Author'),
  ('10000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-000000000103', 'rls-private-book', 5, 'private post', 'RLS Private Book', 'Test Author'),
  ('10000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-000000000105', 'rls-blocked-book', 3, 'blocked post', 'RLS Blocked Book', 'Test Author');

insert into public.favorites (profile_id, book_id)
values
  ('00000000-0000-4000-8000-000000000101', 'rls-public-book'),
  ('00000000-0000-4000-8000-000000000103', 'rls-private-book');

insert into public.post_replies (id, post_id, profile_id, message)
values
  (900000000101, '10000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102', 'visible reply'),
  (900000000103, '10000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-000000000103', 'private reply');

insert into public.notifications (id, recipient_id, actor_id, type, post_id, reply_id)
values
  (910000000101, '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102', 'reply', '10000000-0000-4000-8000-000000000101', 900000000101),
  (910000000102, '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000101', 'follow', null, null);

insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000105');

insert into public.moderation_reports (id, reporter_id, reported_profile_id, post_id, category, details, post_snapshot)
values (920000000101, '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000101', 'spam', 'seed report', '{"source":"rls-test"}'::jsonb);

insert into public.adult_content_terms (term, is_active)
values ('rls-admin-only-term', true);

insert into public.privacy_password_credentials (profile_id, password_hash)
values ('00000000-0000-4000-8000-000000000101', 'rls-test-hash');

insert into public.privacy_password_recovery_requests (profile_id, provider)
values ('00000000-0000-4000-8000-000000000101', 'email');

select test_auth('anon');

select results_eq($$select id from public.profiles where id = '00000000-0000-4000-8000-000000000101'::uuid$$, $$values ('00000000-0000-4000-8000-000000000101'::uuid)$$, 'anon can read public profile identity');
select results_eq($$select id from public.posts where id = '10000000-0000-4000-8000-000000000101'::uuid$$, $$values ('10000000-0000-4000-8000-000000000101'::uuid)$$, 'anon can read a public profile post');
select is_empty($$select id from public.posts where id = '10000000-0000-4000-8000-000000000103'::uuid$$, 'anon cannot read a private profile post');
select results_eq($$select profile_id, book_id from public.favorites where profile_id = '00000000-0000-4000-8000-000000000101'::uuid$$, $$values ('00000000-0000-4000-8000-000000000101'::uuid, 'rls-public-book'::text)$$, 'anon can read public favorites');
select is_empty($$select profile_id from public.favorites where profile_id = '00000000-0000-4000-8000-000000000103'::uuid$$, 'anon cannot read private favorites');
select results_eq($$select id from public.post_replies where id = 900000000101$$, $$values (900000000101::bigint)$$, 'anon can read replies visible through a public post and public replier');
select is_empty($$select id from public.post_replies where id = 900000000103$$, 'anon cannot read replies on private profile content');
select is_empty($select id from public.notifications where id = 910000000101$, 'anon cannot read notifications');
select is_empty($select blocker_id from public.blocks where blocker_id = '00000000-0000-4000-8000-000000000101'::uuid$, 'anon cannot read block settings');
select throws_ok($insert into public.posts (profile_id, book_id, rating, comment, book_title) values ('00000000-0000-4000-8000-000000000101', 'rls-anon-write', 3, 'anon write', 'Anon Write')$, '42501', 'new row violates row-level security policy for table "posts"', 'anon cannot insert posts');
-- Use a book already posted by this profile so the trigger cannot short-circuit
-- before the test exercises the anonymous INSERT RLS policy.
select throws_ok($insert into public.favorites (profile_id, book_id) values ('00000000-0000-4000-8000-000000000101', 'rls-owner-delete-book')$, '42501', 'new row violates row-level security policy for table "favorites"', 'anon cannot insert favorites');
select throws_ok($$select public.create_post_reply('10000000-0000-4000-8000-000000000101'::uuid, 'anon reply', null::bigint, false)$$, '42501', 'permission denied for function create_post_reply', 'anon cannot create replies through reply RPC');
select throws_ok($insert into public.notifications (recipient_id, actor_id, type) values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102', 'follow')$, '42501', 'new row violates row-level security policy for table "notifications"', 'anon cannot create notifications directly');

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_auth('authenticated', '00000000-0000-4000-8000-000000000101');

select results_eq($$select id from public.posts where id = '10000000-0000-4000-8000-000000000101'::uuid$$, $$values ('10000000-0000-4000-8000-000000000101'::uuid)$$, 'authenticated user can read visible public post');
select is_empty($$select id from public.posts where id = '10000000-0000-4000-8000-000000000103'::uuid$$, 'authenticated user cannot read another user private post');
select is_empty($$select id from public.posts where id = '10000000-0000-4000-8000-000000000105'::uuid$$, 'blocked user content is hidden by RLS');
select lives_ok($$update public.profiles set bio = 'owner updated bio', is_private = true where id = '00000000-0000-4000-8000-000000000101'::uuid$$, 'authenticated user can update allowed fields on own profile');
select is((select bio from public.profiles where id = '00000000-0000-4000-8000-000000000101'::uuid), 'owner updated bio', 'own profile update takes effect');
select is((select is_private from public.profiles where id = '00000000-0000-4000-8000-000000000101'::uuid), true, 'own privacy setting update takes effect');
select lives_ok($$update public.posts set comment = 'owner edited post', rating = 4.5 where id = '10000000-0000-4000-8000-000000000101'::uuid$$, 'post owner can update own post');
select lives_ok($$delete from public.posts where id = '10000000-0000-4000-8000-000000000102'::uuid and profile_id = '00000000-0000-4000-8000-000000000101'::uuid$$, 'post owner can delete own post');

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
update public.profiles
set is_private = false
where id = '00000000-0000-4000-8000-000000000101'::uuid;
select test_auth('authenticated', '00000000-0000-4000-8000-000000000101');

select results_eq($$with rows as (update public.profiles set bio = 'should not update other profile' where id = '00000000-0000-4000-8000-000000000102'::uuid returning 1) select count(*)::bigint from rows$$, $$values (0::bigint)$$, 'authenticated user cannot update another profile row');
select results_eq($$with rows as (update public.profiles set is_private = false where id = '00000000-0000-4000-8000-000000000103'::uuid returning 1) select count(*)::bigint from rows$$, $$values (0::bigint)$$, 'privacy setting is mutable only by the owner');
select results_eq($$with rows as (update public.posts set comment = 'should not update other post' where id = '10000000-0000-4000-8000-000000000103'::uuid returning 1) select count(*)::bigint from rows$$, $$values (0::bigint)$$, 'authenticated user cannot update another user post');
select results_eq($$with rows as (delete from public.posts where id = '10000000-0000-4000-8000-000000000103'::uuid returning 1) select count(*)::bigint from rows$$, $$values (0::bigint)$$, 'authenticated user cannot delete another user post');
select throws_ok($insert into public.notifications (recipient_id, actor_id, type) values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102', 'follow')$, '42501', 'new row violates row-level security policy for table "notifications"', 'authenticated user cannot create notifications directly');
select results_eq($$select id from public.notifications where id = 910000000101$$, $$values (910000000101::bigint)$$, 'authenticated user reads only own notifications');
select lives_ok($$update public.notifications set read_at = timezone('utc'::text, now()) where id = 910000000101$$, 'notification recipient can mark own notification read');
select results_eq($$with rows as (update public.notifications set read_at = timezone('utc'::text, now()) where id = 910000000102 returning 1) select count(*)::bigint from rows$$, $$values (0::bigint)$$, 'authenticated user cannot update another user notification');
select results_eq($$select blocker_id, blocked_id from public.blocks$$, $$values ('00000000-0000-4000-8000-000000000101'::uuid, '00000000-0000-4000-8000-000000000105'::uuid)$$, 'authenticated user can read blocks they created');
select lives_ok($$select public.unblock_profile('00000000-0000-4000-8000-000000000105'::uuid)$$, 'authenticated user can unblock own block target through RPC');
select is_empty($$select blocker_id from public.blocks where blocked_id = '00000000-0000-4000-8000-000000000105'::uuid$$, 'unblock RPC removes only caller-owned block row');
select lives_ok($$select public.block_profile('00000000-0000-4000-8000-000000000105'::uuid)$$, 'authenticated user can create own block through RPC');
select throws_ok($insert into public.blocks (blocker_id, blocked_id) values ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000103')$, '42501', 'new row violates row-level security policy for table "blocks"', 'authenticated user cannot create arbitrary block rows directly');
select is_empty($$select * from public.moderation_reports$$, 'non-admin authenticated user cannot read moderation reports');
select results_eq($with changed as (update public.moderation_reports set status = 'resolved' where id = 920000000101 returning 1) select count(*)::bigint from changed$, $values (0::bigint)$, 'non-admin authenticated user cannot update moderation reports directly');
select throws_ok($$select public.admin_resolve_report(920000000101, 'not admin')$$, 'P0001', 'Administrator access required', 'non-admin authenticated user cannot execute admin resolve RPC successfully');
select throws_ok($$select public.admin_set_account_suspension('00000000-0000-4000-8000-000000000102'::uuid, true, 'not admin')$$, 'P0001', 'Administrator access required', 'non-admin authenticated user cannot execute admin suspension RPC successfully');
select is_empty($$select * from public.adult_content_terms$$, 'non-admin authenticated user cannot read adult content terms');
select throws_ok($$select * from public.privacy_password_credentials$$, '42501', 'permission denied for table privacy_password_credentials', 'authenticated user cannot read privacy password credentials directly');
select throws_ok($$select * from public.privacy_password_recovery_requests$$, '42501', 'permission denied for table privacy_password_recovery_requests', 'authenticated user cannot read privacy password recovery requests directly');

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_auth('authenticated', '00000000-0000-4000-8000-000000000103');

select results_eq($$select id from public.posts where id = '10000000-0000-4000-8000-000000000103'::uuid$$, $$values ('10000000-0000-4000-8000-000000000103'::uuid)$$, 'private profile owner can read own private post');
select results_eq($$select profile_id from public.favorites where profile_id = '00000000-0000-4000-8000-000000000103'::uuid$$, $$values ('00000000-0000-4000-8000-000000000103'::uuid)$$, 'private profile owner can read own private favorites');

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_auth('authenticated', '00000000-0000-4000-8000-000000000102');

select is_empty($$select id from public.posts where id = '10000000-0000-4000-8000-000000000103'::uuid$$, 'authenticated non-follower cannot read private profile post');
select is_empty($$select profile_id from public.favorites where profile_id = '00000000-0000-4000-8000-000000000103'::uuid$$, 'authenticated non-follower cannot read private profile favorites');
select is_empty($$select id from public.post_replies where id = 900000000103$$, 'authenticated non-follower cannot read private post replies');
select lives_ok($$select public.create_post_reply('10000000-0000-4000-8000-000000000101'::uuid, 'allowed reply', null::bigint, false)$$, 'entitled authenticated user can create a reply on visible post through RPC');
select throws_ok($$select public.create_post_reply('10000000-0000-4000-8000-000000000103'::uuid, 'hidden reply', null::bigint, false)$$, 'P0002', 'Target post is not available', 'authenticated user cannot reply to a hidden private post');
select lives_ok($$delete from public.post_replies where id = 900000000101$$, 'reply owner can delete own reply');
select results_eq($$with rows as (delete from public.post_replies where id = 900000000103 returning 1) select count(*)::bigint from rows$$, $$values (0::bigint)$$, 'authenticated user cannot delete another user reply');
select throws_ok($$update public.post_replies set message = 'reply edits are intentionally unsupported' where id = 900000000103$$, '42501', 'permission denied for table post_replies', 'authenticated user cannot update replies because no update path is granted');
select lives_ok($$select public.submit_post_report('10000000-0000-4000-8000-000000000101'::uuid, 'harassment', 'valid report')$$, 'authenticated user can submit a report for another user post through RPC');
select throws_ok($$select public.submit_post_report('10000000-0000-4000-8000-000000000101'::uuid, 'not_a_category', 'invalid report')$$, 'P0001', 'Invalid report category', 'report RPC rejects invalid categories');

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_auth('authenticated', '00000000-0000-4000-8000-000000000104');

select throws_ok($$select public.create_post_reply('10000000-0000-4000-8000-000000000101'::uuid, 'not entitled', null::bigint, false)$$, '42501', 'Reply entitlement is required', 'authenticated user without reply entitlement cannot create replies');
select results_eq($$select id from public.moderation_reports where id = 920000000101$$, $$values (920000000101::bigint)$$, 'admin can read moderation reports');
select results_eq($$select term from public.adult_content_terms where term = 'rls-admin-only-term'$$, $$values ('rls-admin-only-term'::text)$$, 'admin can read moderation-only adult content terms');
select lives_ok($$select public.admin_resolve_report(920000000101, 'reviewed by admin')$$, 'admin can resolve reports through admin RPC');
select is((select status from public.moderation_reports where id = 920000000101), 'resolved', 'admin report resolution updates moderation report status');

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);

select ok((select prosecdef from pg_proc where oid = 'public.is_current_user_admin()'::regprocedure), 'admin check function is security definer');
select ok((select prosecdef from pg_proc where oid = 'public.submit_post_report(uuid,text,text)'::regprocedure), 'report submission RPC is security definer');
select ok((select prosecdef from pg_proc where oid = 'public.create_post_reply(uuid,text,bigint,boolean)'::regprocedure), 'reply creation RPC is security definer');
select ok(not has_function_privilege('anon', 'public.admin_delete_reported_post(bigint)', 'execute'), 'anon cannot execute admin post deletion RPC');
select ok(has_function_privilege('authenticated', 'public.admin_delete_reported_post(bigint)', 'execute'), 'authenticated users reach the admin RPC authorization check');
select ok(not has_function_privilege('anon', 'public.create_post_reply(uuid,text,bigint,boolean)', 'execute'), 'anon cannot execute reply creation RPC');
select ok(has_function_privilege('authenticated', 'public.create_post_reply(uuid,text,bigint,boolean)', 'execute'), 'authenticated users reach the reply RPC authorization check');

select * from finish();
rollback;
