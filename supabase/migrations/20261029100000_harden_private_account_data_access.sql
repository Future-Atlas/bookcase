-- Reassert least-privilege grants and owner-only RLS for tables containing
-- registration data. This migration is intentionally idempotent so the same
-- security boundary can be audited and repaired in staging and production.

ALTER TABLE public.account_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_password_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_password_recovery_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.account_details
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.account_details
    TO authenticated;

DROP POLICY IF EXISTS "Users can read their own account details"
    ON public.account_details;
CREATE POLICY "Users can read their own account details"
    ON public.account_details FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = profile_id);

DROP POLICY IF EXISTS "Users can insert their own account details"
    ON public.account_details;
CREATE POLICY "Users can insert their own account details"
    ON public.account_details FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = profile_id);

DROP POLICY IF EXISTS "Users can update their own account details"
    ON public.account_details;
CREATE POLICY "Users can update their own account details"
    ON public.account_details FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = profile_id)
    WITH CHECK ((SELECT auth.uid()) = profile_id);

REVOKE ALL ON TABLE public.legal_consents
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.legal_consents
    TO authenticated;
REVOKE ALL ON SEQUENCE public.legal_consents_id_seq
    FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SEQUENCE public.legal_consents_id_seq
    TO authenticated;

DROP POLICY IF EXISTS "Users can read their own legal consents"
    ON public.legal_consents;
CREATE POLICY "Users can read their own legal consents"
    ON public.legal_consents FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = profile_id);

DROP POLICY IF EXISTS "Users can insert their own legal consents"
    ON public.legal_consents;
CREATE POLICY "Users can insert their own legal consents"
    ON public.legal_consents FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = profile_id);

-- Contact submissions are write-only to browser roles. Operations staff read
-- them through privileged tooling, never through the public Data API roles.
REVOKE ALL ON TABLE public.contact_requests
    FROM PUBLIC, anon, authenticated;
GRANT INSERT ON TABLE public.contact_requests
    TO anon, authenticated;
REVOKE ALL ON SEQUENCE public.contact_requests_id_seq
    FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SEQUENCE public.contact_requests_id_seq
    TO anon, authenticated;

DROP POLICY IF EXISTS "Anyone can submit a contact request"
    ON public.contact_requests;
CREATE POLICY "Anyone can submit a contact request"
    ON public.contact_requests FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        status = 'received'
        AND (profile_id IS NULL OR (SELECT auth.uid()) = profile_id)
    );

-- Password hashes and recovery state must only be reached through the
-- narrowly granted SECURITY DEFINER functions. There is no direct browser
-- table access, including for the owning user.
REVOKE ALL ON TABLE public.privacy_password_credentials
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.privacy_password_recovery_requests
    FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.account_details IS
    'Private registration data. Browser access is restricted by owner-only RLS; it is never a public profile source.';
COMMENT ON TABLE public.contact_requests IS
    'Write-only from browser roles. Reading and status management require a privileged operator path.';
