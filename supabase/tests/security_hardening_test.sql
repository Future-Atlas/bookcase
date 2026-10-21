begin;

select no_plan();

select is(
  to_regprocedure('public.increment_read_count(uuid)')::text,
  null::text,
  'legacy arbitrary-user read-count RPC is removed'
);

set local role anon;

select lives_ok(
  $$
    insert into public.contact_requests (email, category, subject, message)
    select
      'rate-limit@example.test',
      'general',
      'Question ' || value,
      'Contact request ' || value
    from generate_series(1, 5) as value
  $$,
  'anonymous contact sender can submit five requests in 24 hours'
);

select throws_ok(
  $$
    insert into public.contact_requests (email, category, subject, message)
    values (
      ' RATE-LIMIT@EXAMPLE.TEST ',
      'general',
      'Question 6',
      'Contact request 6'
    )
  $$,
  'P0001',
  'CONTACT_RATE_LIMIT_EXCEEDED',
  'sixth normalized anonymous contact request is rejected'
);

reset role;

select * from finish();
rollback;
