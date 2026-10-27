-- Grant individual page colors without enabling the full palette or consuming
-- post-milestone unlock credits.

CREATE TABLE IF NOT EXISTS private.page_color_manual_entitlements (
    profile_id UUID NOT NULL
        REFERENCES public.profiles(id) ON DELETE CASCADE,
    color_key TEXT NOT NULL CHECK (
        color_key IN (
            'red', 'magenta', 'purple', 'gray', 'orange', 'pink',
            'light_blue', 'emerald', 'red_purple', 'yellow_green', 'brown'
        )
    ),
    grant_reason TEXT CHECK (
        grant_reason IS NULL OR char_length(grant_reason) <= 500
    ),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (profile_id, color_key)
);

REVOKE ALL ON TABLE private.page_color_manual_entitlements
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.page_color_manual_entitlements
    TO service_role;

COMMENT ON TABLE private.page_color_manual_entitlements IS
    'Operator-granted individual page colors. These grants do not consume post-milestone unlock credits.';

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
       )
       OR EXISTS (
            SELECT 1
            FROM private.page_color_manual_entitlements AS manual
            WHERE manual.profile_id = p_profile_id
              AND manual.color_key = p_page_color
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

    SELECT count(*)
    INTO selected_unlocks
    FROM private.page_color_post_unlocks AS unlock
    WHERE unlock.profile_id = target_profile_id;

    SELECT COALESCE(
        jsonb_agg(colors.color_key ORDER BY colors.first_unlocked_at),
        '[]'::JSONB
    )
    INTO selected_colors
    FROM (
        SELECT all_unlocks.color_key, min(all_unlocks.unlocked_at) AS first_unlocked_at
        FROM (
            SELECT achievement.color_key, achievement.unlocked_at
            FROM private.page_color_post_unlocks AS achievement
            WHERE achievement.profile_id = target_profile_id
            UNION ALL
            SELECT manual.color_key, manual.granted_at
            FROM private.page_color_manual_entitlements AS manual
            WHERE manual.profile_id = target_profile_id
        ) AS all_unlocks
        GROUP BY all_unlocks.color_key
    ) AS colors;

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

-- Requested one-account exception: unlock red only.
INSERT INTO private.page_color_manual_entitlements (
    profile_id,
    color_key,
    grant_reason
)
SELECT
    profile.id,
    'red',
    'Operator-requested individual color grant on 2026-10-27'
FROM public.profiles AS profile
WHERE profile.id = 'f6cccd37-d24b-4959-8222-0f8dc9abf8a3'::UUID
ON CONFLICT (profile_id, color_key) DO NOTHING;
