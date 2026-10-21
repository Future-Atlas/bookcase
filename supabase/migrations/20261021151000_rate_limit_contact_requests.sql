-- Limit contact submissions without storing another copy of the visitor IP.
-- Authenticated requests are grouped by auth.uid(); anonymous requests are
-- grouped by normalized reply-to email. An advisory transaction lock makes
-- concurrent submissions for the same key count atomically.

CREATE INDEX IF NOT EXISTS contact_requests_profile_created_at_idx
    ON public.contact_requests (profile_id, created_at DESC)
    WHERE profile_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS contact_requests_anonymous_email_created_at_idx
    ON public.contact_requests ((lower(btrim(email))), created_at DESC)
    WHERE profile_id IS NULL;

CREATE OR REPLACE FUNCTION private.enforce_contact_request_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    requester UUID := auth.uid();
    normalized_email TEXT := lower(btrim(NEW.email));
    rate_key TEXT;
    recent_count INTEGER;
BEGIN
    -- A signed-in caller cannot avoid the account limit by sending NULL as
    -- profile_id. The existing RLS policy then verifies this value as usual.
    IF requester IS NOT NULL THEN
        NEW.profile_id := requester;
        rate_key := 'profile:' || requester::text;
    ELSE
        NEW.profile_id := NULL;
        NEW.email := normalized_email;
        rate_key := 'email:' || normalized_email;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(rate_key, 0)
    );

    IF requester IS NOT NULL THEN
        SELECT count(*)
        INTO recent_count
        FROM public.contact_requests
        WHERE profile_id = requester
          AND created_at >= pg_catalog.clock_timestamp() - interval '24 hours';
    ELSE
        SELECT count(*)
        INTO recent_count
        FROM public.contact_requests
        WHERE profile_id IS NULL
          AND lower(btrim(email)) = normalized_email
          AND created_at >= pg_catalog.clock_timestamp() - interval '24 hours';
    END IF;

    IF recent_count >= 5 THEN
        RAISE EXCEPTION 'CONTACT_RATE_LIMIT_EXCEEDED'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_contact_request_rate_limit()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS enforce_contact_request_rate_limit_before_insert
    ON public.contact_requests;

CREATE TRIGGER enforce_contact_request_rate_limit_before_insert
BEFORE INSERT ON public.contact_requests
FOR EACH ROW
EXECUTE FUNCTION private.enforce_contact_request_rate_limit();
