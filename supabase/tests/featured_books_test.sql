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

select has_table('public', 'featured_books', 'featured_books table exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.featured_books'::regclass),
  'featured_books has row level security enabled'
);
select col_is_pk('public', 'featured_books', 'id', 'featured_books.id is the primary key');
select col_is_unique(
  'public',
  'featured_books',
  'book_id',
  'featured_books.book_id is unique'
);

insert into auth.users (id, aud, role, email, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-4000-8000-000000000201', 'authenticated', 'authenticated', 'featured-user@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-4000-8000-000000000202', 'authenticated', 'authenticated', 'featured-admin@example.test', now(), now(), '{}'::jsonb, '{}'::jsonb);

insert into public.profiles (id, username, user_id, bio, is_private, page_color)
values
  ('00000000-0000-4000-8000-000000000201', 'Featured User', 'featured_user', '', false, 'yellow'),
  ('00000000-0000-4000-8000-000000000202', 'Featured Admin', 'featured_admin', '', false, 'yellow');

insert into public.app_admins (profile_id)
values ('00000000-0000-4000-8000-000000000202');

insert into public.featured_books (
  book_id,
  book_title,
  priority,
  starts_at,
  ends_at,
  created_by
)
values
  ('featured-active-001', 'Active Featured Book', 1, now() - interval '1 day', now() + interval '1 day', '00000000-0000-4000-8000-000000000202'),
  ('featured-future-001', 'Future Featured Book', 2, now() + interval '1 day', null, '00000000-0000-4000-8000-000000000202'),
  ('featured-expired-01', 'Expired Featured Book', 3, now() - interval '2 days', now() - interval '1 day', '00000000-0000-4000-8000-000000000202');

select test_auth('anon');

select results_eq(
  $$select book_id from public.featured_books order by book_id$$,
  $$values ('featured-active-001'::text)$$,
  'anonymous visitors can read only active featured books'
);
select throws_ok(
  $$insert into public.featured_books (book_id, book_title) values ('featured-anon-001', 'Anonymous Write')$$,
  '42501',
  'permission denied for table featured_books',
  'anonymous visitors cannot manage featured books'
);

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_auth('authenticated', '00000000-0000-4000-8000-000000000201');

select results_eq(
  $$select book_id from public.featured_books order by book_id$$,
  $$values ('featured-active-001'::text)$$,
  'non-admin users can read only active featured books'
);
select throws_ok(
  $$insert into public.featured_books (book_id, book_title) values ('featured-user-001', 'User Write')$$,
  '42501',
  'new row violates row-level security policy for table "featured_books"',
  'non-admin users cannot create featured books'
);

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);
select test_auth('authenticated', '00000000-0000-4000-8000-000000000202');

select results_eq(
  $$select book_id from public.featured_books order by book_id$$,
  $$values ('featured-active-001'::text), ('featured-expired-01'::text), ('featured-future-001'::text)$$,
  'administrators can read active, future, and expired featured books'
);
select lives_ok(
  $$insert into public.featured_books (book_id, book_title, created_by) values ('featured-admin-01', 'Administrator Write', '00000000-0000-4000-8000-000000000202')$$,
  'administrators can create featured books'
);
select lives_ok(
  $$update public.featured_books set priority = 10 where book_id = 'featured-admin-01'$$,
  'administrators can update featured books'
);
select lives_ok(
  $$delete from public.featured_books where book_id = 'featured-admin-01'$$,
  'administrators can delete featured books'
);

reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
