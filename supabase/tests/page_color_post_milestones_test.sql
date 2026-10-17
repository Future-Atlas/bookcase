begin;

select no_plan();

create or replace function test_page_color_auth(test_uid uuid)
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
  '76000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'color-achievement@example.test',
  now(),
  now(),
  '{}'::jsonb,
  '{}'::jsonb
);

insert into public.profiles (id, username, user_id, bio, is_private)
values (
  '76000000-0000-4000-8000-000000000001',
  'Color Achievement',
  'color_achievement',
  '',
  false
);

select test_page_color_auth('76000000-0000-4000-8000-000000000001');

select is(
  (public.current_user_page_color_access()->>'unlocks_remaining')::integer,
  0,
  'a new account has no achievement unlock credit'
);
select is(
  (public.current_user_page_color_access()->>'next_milestone')::integer,
  10,
  'the first page-color milestone is 10 posts'
);
select throws_ok(
  $$select public.unlock_current_user_page_color('red')$$,
  '42501',
  'page_color_unlock_not_earned',
  'a non-basic color cannot be unlocked before the first milestone'
);

insert into public.posts (
  id, profile_id, book_id, rating, comment, book_title, book_author
)
select
  gen_random_uuid(),
  '76000000-0000-4000-8000-000000000001'::uuid,
  'color-book-' || number,
  4,
  'milestone post ' || number,
  'Color Book ' || number,
  'Test Author'
from generate_series(1, 10) as number;

select is(
  (public.current_user_page_color_access()->>'unlocks_remaining')::integer,
  1,
  '10 posts earn one selectable color'
);
select lives_ok(
  $$select public.unlock_current_user_page_color('red')$$,
  'the member may choose red as the first earned color'
);
select lives_ok(
  $$select public.update_profile_page_color('red')$$,
  'an earned color may be selected as the profile color'
);
select throws_ok(
  $$select public.unlock_current_user_page_color('purple')$$,
  '42501',
  'page_color_unlock_not_earned',
  'the same milestone cannot unlock a second color'
);

insert into public.posts (
  id, profile_id, book_id, rating, comment, book_title, book_author
)
select
  gen_random_uuid(),
  '76000000-0000-4000-8000-000000000001'::uuid,
  'color-book-' || number,
  4,
  'milestone post ' || number,
  'Color Book ' || number,
  'Test Author'
from generate_series(11, 25) as number;

select is(
  (public.current_user_page_color_access()->>'unlocks_remaining')::integer,
  1,
  '25 posts earn a second selectable color after the first is used'
);
select lives_ok(
  $$select public.unlock_current_user_page_color('purple')$$,
  'the member may choose a second color at 25 posts'
);

delete from public.posts
where profile_id = '76000000-0000-4000-8000-000000000001'::uuid;

select lives_ok(
  $$select public.update_profile_page_color('purple')$$,
  'an already unlocked color remains available after posts are deleted'
);

select is(
  (public.current_user_page_color_access()->>'next_milestone')::integer,
  50,
  'deleted posts do not make an already-used milestone available again'
);

reset role;

select is(
  (
    select count(*)::integer
    from private.page_color_post_unlocks
    where profile_id = '76000000-0000-4000-8000-000000000001'::uuid
  ),
  2,
  'selected achievement colors are stored permanently'
);

select * from finish();
rollback;
