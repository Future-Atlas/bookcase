-- Keep the next page-color milestone monotonic after an earned color has been
-- selected. Selected colors are permanent even if the member later deletes
-- posts, so an already-used milestone must never be advertised or earned again.

CREATE OR REPLACE FUNCTION private.page_color_milestone_for_slot(
    p_slot INTEGER
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN p_slot IS NULL OR p_slot < 1 OR p_slot > 11 THEN NULL
        WHEN p_slot = 1 THEN 10
        WHEN p_slot = 2 THEN 25
        WHEN p_slot = 3 THEN 50
        WHEN p_slot = 4 THEN 100
        ELSE 100 + (p_slot - 4) * 50
    END;
$$;

REVOKE ALL ON FUNCTION private.page_color_milestone_for_slot(INTEGER)
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
    next_unlock_slot INTEGER := 0;
    next_milestone INTEGER := NULL;
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

    SELECT count(*), COALESCE(
        jsonb_agg(unlock.color_key ORDER BY unlock.unlocked_at),
        '[]'::JSONB
    )
    INTO selected_unlocks, selected_colors
    FROM private.page_color_post_unlocks AS unlock
    WHERE unlock.profile_id = target_profile_id;

    next_unlock_slot := GREATEST(earned_unlocks, selected_unlocks) + 1;
    next_milestone := private.page_color_milestone_for_slot(next_unlock_slot);

    RETURN jsonb_build_object(
        'can_use_all', has_full_palette,
        'post_count', current_post_count,
        'earned_unlocks', earned_unlocks,
        'unlocked_colors', selected_colors,
        'unlocks_remaining', GREATEST(earned_unlocks - selected_unlocks, 0),
        'next_milestone', next_milestone
    );
END;
$$;

REVOKE ALL ON FUNCTION public.current_user_page_color_access()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_page_color_access()
    TO authenticated;

COMMENT ON FUNCTION private.page_color_milestone_for_slot(INTEGER) IS
    'Returns the completed-book threshold for a permanent color unlock slot.';
COMMENT ON FUNCTION public.current_user_page_color_access() IS
    'Returns permanent color unlocks and the next milestone after both earned and already-used slots.';
