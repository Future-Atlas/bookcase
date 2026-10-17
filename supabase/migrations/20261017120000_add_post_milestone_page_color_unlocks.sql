-- Let members permanently unlock one non-basic profile color at each review
-- milestone while preserving the existing Premium and legacy full-palette
-- entitlements. The earned slot count is derived from the current post count,
-- but a color already chosen remains unlocked if posts are later deleted.

CREATE TABLE IF NOT EXISTS private.page_color_post_unlocks (
    profile_id UUID NOT NULL
        REFERENCES public.profiles(id) ON DELETE CASCADE,
    color_key TEXT NOT NULL CHECK (
        color_key IN (
            'red', 'magenta', 'purple', 'gray', 'orange', 'pink',
            'light_blue', 'emerald', 'red_purple', 'yellow_green', 'brown'
        )
    ),
    post_count_at_unlock INTEGER NOT NULL CHECK (post_count_at_unlock >= 0),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (profile_id, color_key)
);

REVOKE ALL ON TABLE private.page_color_post_unlocks
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.page_color_post_unlocks
    TO service_role;

CREATE OR REPLACE FUNCTION private.page_color_unlock_slots(
    p_post_count BIGINT
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT LEAST(
        11,
        CASE
            WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 10 THEN 0
            WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 25 THEN 1
            WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 50 THEN 2
            WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 100 THEN 3
            ELSE 4 + floor(
                (GREATEST(COALESCE(p_post_count, 0), 0) - 100) / 50.0
            )::INTEGER
        END
    );
$$;

REVOKE ALL ON FUNCTION private.page_color_unlock_slots(BIGINT)
    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.page_color_next_milestone(
    p_post_count BIGINT
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN private.page_color_unlock_slots(p_post_count) >= 11 THEN NULL
        WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 10 THEN 10
        WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 25 THEN 25
        WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 50 THEN 50
        WHEN GREATEST(COALESCE(p_post_count, 0), 0) < 100 THEN 100
        ELSE 100 + 50 * (
            floor((GREATEST(COALESCE(p_post_count, 0), 0) - 100) / 50.0)::INTEGER + 1
        )
    END;
$$;

REVOKE ALL ON FUNCTION private.page_color_next_milestone(BIGINT)
    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.profile_can_use_page_color(
    p_profile_id UUID,
    p_page_color TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT p_page_color IN ('blue', 'yellow', 'green')
       OR private.profile_effective_subscription_plan(p_profile_id) = 'premium'
       OR EXISTS (
            SELECT 1
            FROM private.page_color_legacy_entitlements AS legacy
            WHERE legacy.profile_id = p_profile_id
       )
       OR EXISTS (
            SELECT 1
            FROM private.page_color_post_unlocks AS achievement
            WHERE achievement.profile_id = p_profile_id
              AND achievement.color_key = p_page_color
       );
$$;

REVOKE ALL ON FUNCTION private.profile_can_use_page_color(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.current_user_page_color_access()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_profile_id UUID := auth.uid();
    current_post_count BIGINT := 0;
    earned_unlocks INTEGER := 0;
    selected_unlocks INTEGER := 0;
    has_full_palette BOOLEAN := false;
    selected_colors JSONB := '[]'::JSONB;
BEGIN
    IF target_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    SELECT count(*)
    INTO current_post_count
    FROM public.posts AS post
    WHERE post.profile_id = target_profile_id;

    earned_unlocks := private.page_color_unlock_slots(current_post_count);
    has_full_palette := public.current_user_can_use_all_page_colors();

    SELECT count(*), COALESCE(jsonb_agg(unlock.color_key ORDER BY unlock.unlocked_at), '[]'::JSONB)
    INTO selected_unlocks, selected_colors
    FROM private.page_color_post_unlocks AS unlock
    WHERE unlock.profile_id = target_profile_id;

    RETURN jsonb_build_object(
        'can_use_all', has_full_palette,
        'post_count', current_post_count,
        'earned_unlocks', earned_unlocks,
        'unlocked_colors', selected_colors,
        'unlocks_remaining', GREATEST(earned_unlocks - selected_unlocks, 0),
        'next_milestone', private.page_color_next_milestone(current_post_count)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.current_user_page_color_access()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_page_color_access()
    TO authenticated;

CREATE OR REPLACE FUNCTION public.unlock_current_user_page_color(
    p_page_color TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_profile_id UUID := auth.uid();
    current_post_count BIGINT := 0;
    earned_unlocks INTEGER := 0;
    selected_unlocks INTEGER := 0;
BEGIN
    IF target_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_page_color IS NULL OR p_page_color NOT IN (
        'red', 'magenta', 'purple', 'gray', 'orange', 'pink',
        'light_blue', 'emerald', 'red_purple', 'yellow_green', 'brown'
    ) THEN
        RAISE EXCEPTION 'Invalid unlockable page color' USING ERRCODE = '23514';
    END IF;

    PERFORM 1
    FROM public.profiles AS profile
    WHERE profile.id = target_profile_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM private.page_color_post_unlocks AS existing
        WHERE existing.profile_id = target_profile_id
          AND existing.color_key = p_page_color
    ) THEN
        RETURN public.current_user_page_color_access();
    END IF;

    SELECT count(*)
    INTO current_post_count
    FROM public.posts AS post
    WHERE post.profile_id = target_profile_id;

    earned_unlocks := private.page_color_unlock_slots(current_post_count);

    SELECT count(*)
    INTO selected_unlocks
    FROM private.page_color_post_unlocks AS unlock
    WHERE unlock.profile_id = target_profile_id;

    IF selected_unlocks >= earned_unlocks THEN
        RAISE EXCEPTION 'page_color_unlock_not_earned'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO private.page_color_post_unlocks (
        profile_id,
        color_key,
        post_count_at_unlock
    ) VALUES (
        target_profile_id,
        p_page_color,
        current_post_count::INTEGER
    );

    RETURN public.current_user_page_color_access();
END;
$$;

REVOKE ALL ON FUNCTION public.unlock_current_user_page_color(TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlock_current_user_page_color(TEXT)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_profile_page_color_entitlement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT private.profile_can_use_page_color(NEW.id, NEW.page_color) THEN
        RAISE EXCEPTION 'page_color_access_required'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_profile_page_color_entitlement()
    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_profile_page_color(
    p_page_color TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_profile_id UUID := auth.uid();
BEGIN
    IF target_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_page_color IS NULL OR p_page_color NOT IN (
        'red', 'magenta', 'blue', 'yellow', 'green', 'purple', 'gray',
        'orange', 'pink', 'light_blue', 'emerald', 'red_purple',
        'yellow_green', 'brown'
    ) THEN
        RAISE EXCEPTION 'Invalid page color' USING ERRCODE = '23514';
    END IF;

    IF NOT private.profile_can_use_page_color(target_profile_id, p_page_color) THEN
        RAISE EXCEPTION 'page_color_access_required'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.profiles
    SET page_color = p_page_color
    WHERE id = target_profile_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0002';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_profile_page_color(TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_profile_page_color(TEXT)
    TO authenticated;

COMMENT ON TABLE private.page_color_post_unlocks IS
    'Permanent non-basic profile colors selected after reaching post-count milestones.';
COMMENT ON FUNCTION public.current_user_page_color_access() IS
    'Returns full-palette access, current post progress, permanent selected colors, and the next milestone.';
COMMENT ON FUNCTION public.unlock_current_user_page_color(TEXT) IS
    'Permanently unlocks one selected non-basic color for each earned post-count milestone.';
