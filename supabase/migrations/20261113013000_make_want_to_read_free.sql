-- Want-to-read is a standard feature for all authenticated, active users.
-- Preserve every existing shelf row and post engagement. Keep profile privacy,
-- block relationships and the authenticated RPC mutation boundary unchanged.

CREATE OR REPLACE FUNCTION public.current_user_can_use_want_to_read()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT auth.uid() IS NOT NULL
       AND public.is_profile_active(auth.uid());
$$;

REVOKE ALL ON FUNCTION public.current_user_can_use_want_to_read() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_can_use_want_to_read()
    TO anon, authenticated;

COMMENT ON FUNCTION public.current_user_can_use_want_to_read() IS
    'Active signed-in members can use the free want-to-read feature.';

CREATE OR REPLACE FUNCTION public.profile_can_expose_want_to_read(
    target_profile_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT public.can_view_profile_content(target_profile_id);
$$;

REVOKE ALL ON FUNCTION public.profile_can_expose_want_to_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_can_expose_want_to_read(UUID)
    TO anon, authenticated;

DROP POLICY IF EXISTS "Active subscriber want-to-read shelves can be read"
    ON public.want_to_read_books;
DROP POLICY IF EXISTS "Visible want-to-read shelves can be read"
    ON public.want_to_read_books;
CREATE POLICY "Visible want-to-read shelves can be read"
    ON public.want_to_read_books FOR SELECT
    USING (public.profile_can_expose_want_to_read(profile_id));

-- Reapply the hardened visibility-aware aggregate introduced by
-- 20261102183000: do not reveal private, blocked or age-restricted reviews.
-- The free reading-list count now includes visible shelves on all plans,
-- because profile_can_expose_want_to_read no longer gates by subscription.
CREATE OR REPLACE FUNCTION public.get_book_engagement_counts(target_book_id TEXT)
RETURNS TABLE(read_count BIGINT, want_to_read_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.get_book_engagement_counts(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_book_engagement_counts(TEXT)
    TO anon, authenticated;
