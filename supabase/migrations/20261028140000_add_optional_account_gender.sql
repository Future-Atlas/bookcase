-- Store the optional registration gender separately from the public profile.
-- Existing accounts remain valid and are treated as "undisclosed".

ALTER TABLE public.account_details
    ADD COLUMN IF NOT EXISTS gender TEXT NOT NULL DEFAULT 'undisclosed';

-- At this migration point every existing Sharemarium account is an
-- operator-managed male account. This one-time backfill does not affect users
-- who register after the migration; new registrations keep their own choice.
UPDATE public.account_details
SET gender = 'male'
WHERE gender = 'undisclosed';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'account_details_gender_check'
          AND conrelid = 'public.account_details'::regclass
    ) THEN
        ALTER TABLE public.account_details
            ADD CONSTRAINT account_details_gender_check CHECK (
                gender IN ('female', 'male', 'undisclosed')
            );
    END IF;
END;
$$;

COMMENT ON COLUMN public.account_details.gender IS
    'Private optional registration gender: female, male, or undisclosed. Not published on profiles.';

-- Keep the former overload available so a previously deployed client remains
-- usable while this migration and the new client are rolled out.
CREATE OR REPLACE FUNCTION public.complete_registration(
    p_family_name TEXT,
    p_given_name TEXT,
    p_gender TEXT,
    p_birth_date DATE,
    p_phone_number TEXT,
    p_username TEXT,
    p_user_id TEXT,
    p_privacy_password TEXT,
    p_guardian_consent BOOLEAN,
    p_terms_version TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions
AS $$
DECLARE
    current_profile_id UUID := auth.uid();
    normalized_gender TEXT := lower(btrim(p_gender));
BEGIN
    IF current_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF normalized_gender NOT IN ('female', 'male', 'undisclosed') THEN
        RAISE EXCEPTION 'Invalid registration gender' USING ERRCODE = '23514';
    END IF;

    PERFORM public.complete_registration(
        p_family_name,
        p_given_name,
        p_birth_date,
        p_phone_number,
        p_username,
        p_user_id,
        p_privacy_password,
        p_guardian_consent,
        p_terms_version
    );

    UPDATE public.account_details
    SET gender = normalized_gender,
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = current_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_registration(
    TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_registration(
    TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT
) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_private_account_details(
    p_password TEXT,
    p_family_name TEXT,
    p_given_name TEXT,
    p_gender TEXT,
    p_birth_date DATE,
    p_phone_number TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    current_profile_id UUID := auth.uid();
    normalized_gender TEXT := lower(btrim(p_gender));
    details_updated BOOLEAN;
BEGIN
    IF current_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF normalized_gender NOT IN ('female', 'male', 'undisclosed') THEN
        RAISE EXCEPTION 'Invalid account gender' USING ERRCODE = '23514';
    END IF;

    details_updated := public.update_private_account_details(
        p_password,
        p_family_name,
        p_given_name,
        p_birth_date,
        p_phone_number
    );
    IF NOT details_updated THEN
        RETURN FALSE;
    END IF;

    UPDATE public.account_details
    SET gender = normalized_gender,
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = current_profile_id;

    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.update_private_account_details(
    TEXT, TEXT, TEXT, TEXT, DATE, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_private_account_details(
    TEXT, TEXT, TEXT, TEXT, DATE, TEXT
) TO authenticated;
