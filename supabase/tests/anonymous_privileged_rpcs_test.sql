begin;
select no_plan();

-- Anonymous callers must never enter the SECURITY DEFINER routines used for
-- account mutation, moderation, password operations or authenticated actions.
with restricted(signature) as (
 values
  ('public.admin_delete_reported_post(bigint)'),
  ('public.admin_delete_reported_reply(bigint)'),
  ('public.admin_resolve_report(bigint,text)'),
  ('public.admin_set_account_suspension(uuid,boolean,text)'),
  ('public.begin_privacy_password_recovery()'),
  ('public.block_profile(uuid)'),
  ('public.change_privacy_password(text,text)'),
  ('public.check_session_ip_change(inet,text)'),
  ('public.create_post_reply(uuid,text,bigint,boolean)'),
  ('public.has_privacy_password()'),
  ('public.initialize_privacy_password(text)'),
  ('public.request_follow(uuid)'),
  ('public.respond_follow_request(uuid,boolean)'),
  ('public.submit_post_report(uuid,text,text)'),
  ('public.submit_reply_report(bigint,text,text)'),
  ('public.toggle_want_to_read(text,text,text,text,uuid)'),
  ('public.unblock_profile(uuid)'),
  ('public.unfollow_profile(uuid)'),
  ('public.update_private_account_details(text,text,date,text)'),
  ('public.update_public_profile(text,text,boolean)'),
  ('public.verify_privacy_password(text)')
)
select ok(
 to_regprocedure(signature) is not null
 and has_function_privilege('anon', to_regprocedure(signature), 'EXECUTE') = false,
 'anonymous EXECUTE revoked: ' || signature
) from restricted;

-- Expected authenticated API entrypoints remain available. Their function
-- bodies continue to enforce auth.uid() and (where needed) administrator role.
with authorized(signature) as (
 values
  ('public.admin_set_account_suspension(uuid,boolean,text)'),
  ('public.create_post_reply(uuid,text,bigint,boolean)'),
  ('public.begin_privacy_password_recovery()'),
  ('public.verify_privacy_password(text)')
)
select ok(
 has_function_privilege('authenticated', to_regprocedure(signature), 'EXECUTE') = true,
 'signed-in role retains permission: ' || signature
) from authorized;

-- Public read-access helpers remain callable so existing profile and
-- book-visibility RLS policies continue to work for anonymous readers.
select ok(
 has_function_privilege('anon', 'public.can_view_profile_content(uuid)', 'EXECUTE'),
 'anonymous public post visibility helper remains callable'
);

with private_helpers(signature) as (
 values
  ('private.normalize_denial_name(text)'),
  ('private.normalize_denial_email(text)'),
  ('private.normalize_denial_phone(text)')
)
select ok(
 exists (
   select 1 from pg_proc p
   where p.oid = to_regprocedure(signature)
     and 'search_path=pg_catalog' = any(p.proconfig)
 ),
 'private normalization search_path is pinned: ' || signature
) from private_helpers;

select * from finish();
rollback;
