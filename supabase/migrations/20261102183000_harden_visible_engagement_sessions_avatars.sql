-- Prevent private reading-activity counts leaking through a definer RPC.
-- Apply the identical visibility predicates as the posts and want-to-read
-- table RLS policies. Do not change the public RPC signature or columns.
CREATE OR REPLACE FUNCTION public.get_book_engagement_counts(target_book_id text)
RETURNS TABLE(read_count bigint, want_to_read_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
  SELECT
    (SELECT count(*)
       FROM public.posts AS post
      WHERE post.book_id = target_book_id
        AND public.can_view_profile_content(post.profile_id)
        AND (post.is_age_restricted IS FALSE
             OR public.current_user_can_view_age_restricted())),
    (SELECT count(*)
       FROM public.want_to_read_books AS wanted
      WHERE wanted.book_id = target_book_id
        AND public.profile_can_expose_want_to_read(wanted.profile_id));
$body$;

-- The previous session-IP RPC accepted arbitrary IP values from any signed-in
-- browser. Remove its Data API access. The server-only replacement checks
-- the verified session id against the actual GoTrue sessions table.
REVOKE ALL ON FUNCTION public.check_session_ip_change(inet,text)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_active_auth_session(
  p_profile_id uuid, p_session_id uuid
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
  SELECT p_profile_id IS NOT NULL
    AND p_session_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM auth.sessions AS s
      WHERE s.id = p_session_id AND s.user_id = p_profile_id
        AND (s.not_after IS NULL OR s.not_after > now())
    );
$body$;

REVOKE ALL ON FUNCTION public.is_active_auth_session(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_auth_session(uuid,uuid)
  TO service_role;

-- Public uploaded avatars are only permitted from Sharemarium-controlled
-- Supabase Storage projects. Validate on INSERT / avatar_url modification,
-- leaving historical URLs untouched until operators can migrate user assets.
CREATE OR REPLACE FUNCTION public.enforce_allowed_avatar_url()
RETURNS trigger
LANGUAGE plpgsql SET search_path = ''
AS $body$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.avatar_url IS DISTINCT FROM OLD.avatar_url THEN
    IF coalesce(NEW.avatar_url, '') <> ''
       AND NEW.avatar_url !~ (
         '^https://(jeyxadmkbzgpkveomesz|wpoigmywpewrrbudqhgh)[.]supabase[.]co'
         || '/storage/v1/object/public/avatars/'
         || NEW.id::text
         || '/avatar[.](jpg|png|webp)([?]v=[0-9]{1,20})?$'
       )
    THEN
      RAISE EXCEPTION 'avatar_url_source_not_allowed'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$body$;

REVOKE ALL ON FUNCTION public.enforce_allowed_avatar_url()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS enforce_allowed_avatar_url_trigger ON public.profiles;
CREATE TRIGGER enforce_allowed_avatar_url_trigger
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.enforce_allowed_avatar_url();


-- Admins who have a verified MFA factor must present an AAL2 JWT for all
-- moderation RPCs using is_current_user_admin(). This is staged enrollment:
-- before factor enrollment the existing administrator is not unexpectedly
-- locked out; immediately after verifying a TOTP factor, step-up is enforced.
CREATE OR REPLACE FUNCTION public.is_current_user_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
  SELECT EXISTS (
      SELECT 1 FROM public.app_admins WHERE profile_id = auth.uid()
    )
    AND (
      NOT EXISTS (
        SELECT 1 FROM auth.mfa_factors AS factor
        WHERE factor.user_id = auth.uid() AND factor.status = 'verified'
      )
      OR coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
    );
$body$;
