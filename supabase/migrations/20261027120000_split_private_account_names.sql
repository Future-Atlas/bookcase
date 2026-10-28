-- Store private family and given names separately while retaining full_name for
-- compatibility with denial matching, legal retention, and older clients.

ALTER TABLE public.account_details
    ADD COLUMN IF NOT EXISTS family_name TEXT,
    ADD COLUMN IF NOT EXISTS given_name TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'account_details_family_name_check'
          AND conrelid = 'public.account_details'::regclass
    ) THEN
        ALTER TABLE public.account_details
            ADD CONSTRAINT account_details_family_name_check CHECK (
                family_name IS NULL
                OR char_length(btrim(family_name)) BETWEEN 1 AND 50
            );
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'account_details_given_name_check'
          AND conrelid = 'public.account_details'::regclass
    ) THEN
        ALTER TABLE public.account_details
            ADD CONSTRAINT account_details_given_name_check CHECK (
                given_name IS NULL
                OR char_length(btrim(given_name)) BETWEEN 1 AND 50
            );
    END IF;
END;
$$;

COMMENT ON COLUMN public.account_details.family_name IS
    'Private family name. Kept separate so operators do not need to infer name parts from full_name.';
COMMENT ON COLUMN public.account_details.given_name IS
    'Private given name. Kept separate so operators do not need to infer name parts from full_name.';

-- New registrations use this overload. The former p_full_name overload remains
-- available temporarily so an older deployed client is not broken mid-release.
CREATE OR REPLACE FUNCTION public.complete_registration(
    p_family_name TEXT,
    p_given_name TEXT,
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
    normalized_user_id TEXT := lower(p_user_id);
    normalized_phone TEXT := regexp_replace(p_phone_number, '[^0-9+]', '', 'g');
    normalized_family_name TEXT := btrim(p_family_name);
    normalized_given_name TEXT := btrim(p_given_name);
    combined_full_name TEXT := normalized_family_name || ' ' || normalized_given_name;
    is_minor BOOLEAN := p_birth_date > (CURRENT_DATE - INTERVAL '18 years')::date;
BEGIN
    IF current_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF char_length(normalized_family_name) NOT BETWEEN 1 AND 50
       OR char_length(normalized_given_name) NOT BETWEEN 1 AND 50
       OR char_length(combined_full_name) > 100
       OR p_birth_date < DATE '1900-01-01'
       OR p_birth_date > CURRENT_DATE
       OR normalized_phone !~ '^\+?[0-9]{7,15}$'
       OR char_length(btrim(p_username)) NOT BETWEEN 1 AND 30
       OR p_user_id !~ '^[a-zA-Z0-9_]{3,20}$'
       OR normalized_user_id !~ '^[a-z0-9_]{3,20}$'
       OR NOT public.is_valid_privacy_password(p_privacy_password)
       OR char_length(btrim(p_terms_version)) NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'Invalid registration data' USING ERRCODE = '23514';
    END IF;
    IF is_minor AND NOT COALESCE(p_guardian_consent, false) THEN
        RAISE EXCEPTION 'GUARDIAN_CONSENT_REQUIRED' USING ERRCODE = '23514';
    END IF;
    IF normalized_user_id IN (
        'admin', 'administrator', 'support', 'sharemarium', 'system', 'official'
    ) THEN
        RAISE EXCEPTION 'Reserved user ID' USING ERRCODE = '23514';
    END IF;
    IF private.registration_denial_matches(
        combined_full_name, p_birth_date, normalized_phone
    ) THEN
        RAISE EXCEPTION 'REGISTRATION_DENIED' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.profiles
    SET username = btrim(p_username), user_id = normalized_user_id
    WHERE id = current_profile_id;

    INSERT INTO public.account_details (
        profile_id,
        family_name,
        given_name,
        full_name,
        birth_date,
        phone_number,
        guardian_consent_declared_at,
        guardian_consent_terms_version
    ) VALUES (
        current_profile_id,
        normalized_family_name,
        normalized_given_name,
        combined_full_name,
        p_birth_date,
        normalized_phone,
        CASE WHEN is_minor THEN timezone('utc'::text, now()) ELSE NULL END,
        CASE WHEN is_minor THEN btrim(p_terms_version) ELSE NULL END
    )
    ON CONFLICT (profile_id) DO UPDATE
    SET family_name = EXCLUDED.family_name,
        given_name = EXCLUDED.given_name,
        full_name = EXCLUDED.full_name,
        birth_date = EXCLUDED.birth_date,
        phone_number = EXCLUDED.phone_number,
        phone_verified_at = CASE
            WHEN public.account_details.phone_number = EXCLUDED.phone_number
                THEN public.account_details.phone_verified_at
            ELSE NULL
        END,
        guardian_consent_declared_at = EXCLUDED.guardian_consent_declared_at,
        guardian_consent_terms_version = EXCLUDED.guardian_consent_terms_version,
        updated_at = timezone('utc'::text, now());

    INSERT INTO public.privacy_password_credentials (profile_id, password_hash)
    VALUES (
        current_profile_id,
        extensions.crypt(p_privacy_password, extensions.gen_salt('bf', 12))
    )
    ON CONFLICT (profile_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_registration(
    TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_registration(
    TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT
) TO authenticated;

-- New account-settings clients use the split-name overload. full_name remains
-- synchronized for the existing denial and retention functions.
CREATE OR REPLACE FUNCTION public.update_private_account_details(
    p_password TEXT,
    p_family_name TEXT,
    p_given_name TEXT,
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
    normalized_family_name TEXT := btrim(p_family_name);
    normalized_given_name TEXT := btrim(p_given_name);
    combined_full_name TEXT := normalized_family_name || ' ' || normalized_given_name;
    normalized_phone TEXT := regexp_replace(p_phone_number, '[^0-9+]', '', 'g');
BEGIN
    IF current_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF NOT public.verify_privacy_password(p_password) THEN
        RETURN FALSE;
    END IF;
    IF char_length(normalized_family_name) NOT BETWEEN 1 AND 50
       OR char_length(normalized_given_name) NOT BETWEEN 1 AND 50
       OR char_length(combined_full_name) > 100
       OR p_birth_date < DATE '1900-01-01'
       OR p_birth_date > CURRENT_DATE
       OR normalized_phone !~ '^\+?[0-9]{7,15}$' THEN
        RAISE EXCEPTION 'Invalid account details' USING ERRCODE = '23514';
    END IF;

    UPDATE public.account_details
    SET family_name = normalized_family_name,
        given_name = normalized_given_name,
        full_name = combined_full_name,
        birth_date = p_birth_date,
        phone_number = normalized_phone,
        phone_verified_at = CASE
            WHEN phone_number = normalized_phone THEN phone_verified_at
            ELSE NULL
        END,
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = current_profile_id;

    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.update_private_account_details(
    TEXT, TEXT, TEXT, DATE, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_private_account_details(
    TEXT, TEXT, TEXT, DATE, TEXT
) TO authenticated;

-- Keep the separated name attributes in future deletion audit records.
ALTER TABLE private.deleted_accounts
    ADD COLUMN IF NOT EXISTS family_name TEXT,
    ADD COLUMN IF NOT EXISTS given_name TEXT;

CREATE OR REPLACE FUNCTION public.prepare_deleted_account_record(
    target_profile UUID,
    deletion_kind TEXT,
    deleting_admin UUID DEFAULT NULL,
    deletion_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    audit_id UUID;
    target_user auth.users%ROWTYPE;
    profile_record RECORD;
    details_record RECORD;
BEGIN
    IF target_profile IS NULL
       OR deletion_kind NOT IN ('self', 'admin')
       OR (deletion_kind = 'admin' AND deleting_admin IS NULL)
       OR char_length(coalesce(deletion_notes, '')) > 1000 THEN
        RAISE EXCEPTION 'Invalid account deletion audit request'
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO target_user
    FROM auth.users
    WHERE id = target_profile;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auth user not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT username, user_id
    INTO profile_record
    FROM public.profiles
    WHERE id = target_profile;

    SELECT family_name, given_name, full_name, birth_date, phone_number
    INTO details_record
    FROM public.account_details
    WHERE profile_id = target_profile;

    INSERT INTO private.deleted_accounts (
        profile_id,
        username,
        user_id,
        family_name,
        given_name,
        full_name,
        birth_date,
        email,
        phone_number,
        auth_provider,
        deletion_type,
        deleted_by,
        handling_notes
    ) VALUES (
        target_profile,
        profile_record.username,
        profile_record.user_id,
        details_record.family_name,
        details_record.given_name,
        details_record.full_name,
        details_record.birth_date,
        target_user.email,
        details_record.phone_number,
        target_user.raw_app_meta_data ->> 'provider',
        deletion_kind,
        CASE
            WHEN deletion_kind = 'self' THEN target_profile
            ELSE deleting_admin
        END,
        NULLIF(btrim(deletion_notes), '')
    )
    RETURNING id INTO audit_id;

    RETURN audit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_deleted_account_record(UUID, TEXT, UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_deleted_account_record(UUID, TEXT, UUID, TEXT)
    TO service_role;
