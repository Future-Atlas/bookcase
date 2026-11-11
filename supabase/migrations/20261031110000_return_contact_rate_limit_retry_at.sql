-- Return only the next permitted contact time when the rolling 24-hour limit
-- is reached. No contact body, email address, or other personal data is
-- exposed in the error detail.

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
    oldest_counted_at TIMESTAMP WITH TIME ZONE;
    retry_at TIMESTAMP WITH TIME ZONE;
BEGIN
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
        SELECT count(*), min(created_at)
        INTO recent_count, oldest_counted_at
        FROM public.contact_requests
        WHERE profile_id = requester
          AND created_at >= pg_catalog.clock_timestamp() - interval '24 hours';
    ELSE
        SELECT count(*), min(created_at)
        INTO recent_count, oldest_counted_at
        FROM public.contact_requests
        WHERE profile_id IS NULL
          AND lower(btrim(email)) = normalized_email
          AND created_at >= pg_catalog.clock_timestamp() - interval '24 hours';
    END IF;

    IF recent_count >= 5 THEN
        retry_at := oldest_counted_at + interval '24 hours';
        RAISE EXCEPTION 'CONTACT_RATE_LIMIT_EXCEEDED'
            USING ERRCODE = 'P0001',
                  DETAIL = pg_catalog.jsonb_build_object(
                      'retry_at', retry_at
                  )::text;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_contact_request_rate_limit()
    FROM PUBLIC, anon, authenticated;
