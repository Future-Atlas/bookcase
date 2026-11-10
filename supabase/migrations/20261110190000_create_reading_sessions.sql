-- Reading time is recorded by the database clock, never an editable client timestamp.
-- This first release keeps sessions private and does not permit backdating,
-- manual entries, or changes to a completed session.
CREATE TABLE public.reading_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  book_id text NOT NULL CHECK (char_length(book_id) BETWEEN 1 AND 256),
  book_title text NOT NULL CHECK (char_length(book_title) BETWEEN 1 AND 300),
  book_isbn text NOT NULL DEFAULT '' CHECK (char_length(book_isbn) <= 32),
  book_cover_source text NOT NULL DEFAULT '' CHECK (char_length(book_cover_source) <= 48),
  book_cover_url text NOT NULL DEFAULT '' CHECK (char_length(book_cover_url) <= 2048),
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ended_at timestamptz,
  CONSTRAINT reading_sessions_duration_valid CHECK (
    ended_at IS NULL OR
    (ended_at >= started_at AND ended_at <= started_at + interval '24 hours')
  )
);

CREATE INDEX reading_sessions_profile_start_idx
  ON public.reading_sessions(profile_id, started_at DESC);
CREATE UNIQUE INDEX reading_sessions_one_active_per_user_idx
  ON public.reading_sessions(profile_id) WHERE ended_at IS NULL;

ALTER TABLE public.reading_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.reading_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.reading_sessions TO authenticated;

CREATE POLICY "Readers can see only their own reading sessions"
  ON public.reading_sessions
  FOR SELECT TO authenticated
  USING (profile_id = auth.uid());

-- Serialized by locking the authenticated user's profile row, so concurrent
-- requests cannot create multiple active timers for the same user.
CREATE OR REPLACE FUNCTION public.start_reading_session(
  p_book_id text, p_book_title text, p_book_cover_url text DEFAULT '',
  p_book_isbn text DEFAULT '', p_book_cover_source text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  requester uuid := auth.uid();
  new_id uuid;
BEGIN
  IF requester IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  PERFORM 1 FROM public.profiles
    WHERE id = requester AND is_suspended = false
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account unavailable' USING ERRCODE = '42501';
  END IF;

  IF p_book_id IS NULL OR char_length(btrim(p_book_id)) NOT BETWEEN 1 AND 256
     OR p_book_title IS NULL
     OR char_length(btrim(p_book_title)) NOT BETWEEN 1 AND 300
     OR char_length(coalesce(p_book_cover_url, '')) > 2048
     OR char_length(coalesce(p_book_isbn, '')) > 32
     OR char_length(coalesce(p_book_cover_source, '')) > 48 THEN
    RAISE EXCEPTION 'Invalid book data' USING ERRCODE = '23514';
  END IF;

  -- An abandoned session automatically caps at exactly 24 hours.
  UPDATE public.reading_sessions
  SET ended_at = started_at + interval '24 hours'
  WHERE profile_id = requester
    AND ended_at IS NULL
    AND started_at <= clock_timestamp() - interval '24 hours';

  IF EXISTS (
    SELECT 1 FROM public.reading_sessions
    WHERE profile_id = requester AND ended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'reading_session_already_active' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.reading_sessions
      (profile_id, book_id, book_title, book_cover_url,
       book_isbn, book_cover_source)
  VALUES
      (requester, btrim(p_book_id), btrim(p_book_title),
       coalesce(p_book_cover_url, ''),
       coalesce(p_book_isbn, ''), coalesce(p_book_cover_source, ''))
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$body$;

CREATE OR REPLACE FUNCTION public.finish_reading_session(p_session_id uuid)
RETURNS public.reading_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  requester uuid := auth.uid();
  completed public.reading_sessions;
BEGIN
  IF requester IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  UPDATE public.reading_sessions
    SET ended_at = least(clock_timestamp(), started_at + interval '24 hours')
    WHERE id = p_session_id AND profile_id = requester AND ended_at IS NULL
    RETURNING * INTO completed;

  IF NOT FOUND THEN
    SELECT * INTO completed FROM public.reading_sessions
      WHERE id = p_session_id AND profile_id = requester;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Reading session not found' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN completed;
END;
$body$;

REVOKE ALL ON FUNCTION public.start_reading_session(text,text,text,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_reading_session(text,text,text,text,text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.finish_reading_session(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finish_reading_session(uuid)
  TO authenticated;
