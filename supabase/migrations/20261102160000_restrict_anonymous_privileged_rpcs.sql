-- Least privilege for user and administrator mutations: no anonymous RPC access.
-- RLS policies and intentional public read helpers are deliberately unchanged.
-- Existing authenticated and service_role grants remain intact.
-- Anonymous callers cannot legitimately mutate an account: auth.uid() is NULL.
-- 2026-11-02: production Security Advisor reported these grants as anonymous
-- SECURITY DEFINER RPCs. Fail closed before entering privileged function bodies.

REVOKE EXECUTE ON FUNCTION public.admin_delete_reported_post(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_delete_reported_reply(bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_resolve_report(bigint,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_account_suspension(uuid,boolean,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.begin_privacy_password_recovery() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.block_profile(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.change_privacy_password(text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_session_ip_change(inet,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_post_reply(uuid,text,bigint,boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_privacy_password() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.initialize_privacy_password(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.request_follow(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.respond_follow_request(uuid,boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.submit_post_report(uuid,text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.submit_reply_report(bigint,text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.toggle_want_to_read(text,text,text,text,uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.unblock_profile(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.unfollow_profile(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_private_account_details(text,text,date,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_public_profile(text,text,boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.verify_privacy_password(text) FROM PUBLIC, anon;

-- Immutable private normalization functions use only pg_catalog builtins.
-- Pin search_path explicitly so identifiers cannot resolve in caller schemas.
ALTER FUNCTION private.normalize_denial_name(text)
  SET search_path = pg_catalog;
ALTER FUNCTION private.normalize_denial_email(text)
  SET search_path = pg_catalog;
ALTER FUNCTION private.normalize_denial_phone(text)
  SET search_path = pg_catalog;
