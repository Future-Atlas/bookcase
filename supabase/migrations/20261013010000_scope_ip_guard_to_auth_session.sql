-- A fresh, independently authenticated session must not inherit another
-- session's IP baseline. Never accept a session identifier from the client.
CREATE TABLE IF NOT EXISTS public.auth_session_ip_guards (
  session_id UUID PRIMARY KEY,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  initial_ip INET NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  changed_at TIMESTAMPTZ
);
ALTER TABLE public.auth_session_ip_guards ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.auth_session_ip_guards FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.check_session_ip_change(
  p_ip INET, p_user_agent TEXT DEFAULT ''
) RETURNS TABLE (
  ip_changed BOOLEAN, previous_ip TEXT, current_ip TEXT, changed_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user UUID := auth.uid();
  v_session UUID := nullif(auth.jwt()->>'session_id', '')::UUID;
  v_row public.auth_session_ip_guards%ROWTYPE;
BEGIN
  IF v_user IS NULL OR v_session IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_ip IS NULL THEN
    RAISE EXCEPTION 'ip_required' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.auth_session_ip_guards(session_id, profile_id, initial_ip)
    VALUES (v_session, v_user, p_ip) ON CONFLICT (session_id) DO NOTHING;
  SELECT * INTO v_row FROM public.auth_session_ip_guards
    WHERE session_id = v_session AND profile_id = v_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_owner_mismatch' USING ERRCODE = '42501';
  END IF;
  UPDATE public.auth_session_ip_guards AS g
    SET last_seen_at = now(),
        changed_at = CASE WHEN v_row.initial_ip IS DISTINCT FROM p_ip
          THEN coalesce(v_row.changed_at, now()) ELSE v_row.changed_at END
    WHERE g.session_id = v_session RETURNING * INTO v_row;
  RETURN QUERY SELECT v_row.changed_at IS NOT NULL,
    host(v_row.initial_ip), host(p_ip), v_row.changed_at;
END;
$$;
REVOKE ALL ON FUNCTION public.check_session_ip_change(INET, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_session_ip_change(INET, TEXT) TO authenticated;
