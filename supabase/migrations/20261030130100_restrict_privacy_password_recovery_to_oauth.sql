-- Supersedes the email option introduced in 20261030130000.
-- Sharemarium currently authenticates with Google and X only.
-- Keep both migration versions immutable because staging already applied the
-- earlier one; only a *fresh*, matching OAuth login may reset this password.
CREATE OR REPLACE FUNCTION public.begin_privacy_password_recovery()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_provider TEXT := auth.jwt() -> 'app_metadata' ->> 'provider';
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF current_provider NOT IN ('google', 'twitter', 'x') THEN
        RAISE EXCEPTION 'Unsupported recovery provider' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.privacy_password_recovery_requests (
        profile_id, provider, requested_at
    ) VALUES (
        auth.uid(), current_provider, timezone('utc'::text, now())
    )
    ON CONFLICT (profile_id) DO UPDATE
    SET provider = EXCLUDED.provider,
        requested_at = EXCLUDED.requested_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_privacy_password_after_reauthentication(
    p_new_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    recovery public.privacy_password_recovery_requests%ROWTYPE;
    has_recent_oauth BOOLEAN;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_valid_privacy_password(p_new_password) THEN
        RAISE EXCEPTION 'Invalid privacy password' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO recovery
    FROM public.privacy_password_recovery_requests
    WHERE profile_id = auth.uid()
      AND requested_at >= timezone('utc'::text, now()) - interval '15 minutes'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Recovery request expired' USING ERRCODE = '42501';
    END IF;
    IF recovery.provider NOT IN ('google', 'twitter', 'x')
       OR (auth.jwt() -> 'app_metadata' ->> 'provider') IS DISTINCT FROM recovery.provider THEN
        RAISE EXCEPTION 'Recovery provider mismatch' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(auth.jwt() -> 'amr', '[]'::jsonb)) AS entry
        WHERE entry ->> 'method' = 'oauth'
          AND to_timestamp((entry ->> 'timestamp')::double precision)
              >= recovery.requested_at - interval '5 seconds'
    ) INTO has_recent_oauth;
    IF NOT has_recent_oauth THEN
        RAISE EXCEPTION 'Fresh OAuth authentication required' USING ERRCODE = '42501';
    END IF;

    UPDATE public.privacy_password_credentials
    SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
        failed_attempts = 0,
        locked_until = NULL,
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = auth.uid();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Privacy password not initialized' USING ERRCODE = '42501';
    END IF;

    DELETE FROM public.privacy_password_recovery_requests
    WHERE profile_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.begin_privacy_password_recovery() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reset_privacy_password_after_reauthentication(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_privacy_password_recovery() TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_privacy_password_after_reauthentication(TEXT) TO authenticated;
