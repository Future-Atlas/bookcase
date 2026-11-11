-- Following-only reading calendar with a per-follower exclusion list.
-- No historical sessions are changed. All authorization is enforced by RLS.
CREATE TABLE public.reading_calendar_hidden_followers (
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  follower_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  hidden_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (owner_id, follower_id),
  CONSTRAINT reading_calendar_hidden_not_self CHECK (owner_id <> follower_id)
);

CREATE INDEX reading_calendar_hidden_follower_idx
  ON public.reading_calendar_hidden_followers(follower_id, owner_id);

ALTER TABLE public.reading_calendar_hidden_followers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reading_calendar_hidden_followers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.reading_calendar_hidden_followers TO authenticated;

CREATE POLICY "Owner can read calendar exclusions"
  ON public.reading_calendar_hidden_followers
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid());

CREATE OR REPLACE FUNCTION public.can_view_reading_calendar(target_owner uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $body$
  SELECT auth.uid() IS NOT NULL
    AND public.is_profile_active(auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.profiles AS owner
      WHERE owner.id = target_owner
        AND owner.is_suspended = false
        AND (
          owner.id = auth.uid()
          OR (
            NOT public.is_blocked_between(owner.id, auth.uid())
            AND EXISTS (
              SELECT 1 FROM public.follows AS follow
              WHERE follow.follower_id = auth.uid()
                AND follow.following_id = owner.id
                AND follow.status = 'accepted'
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.reading_calendar_hidden_followers AS hidden
              WHERE hidden.owner_id = owner.id
                AND hidden.follower_id = auth.uid()
            )
          )
        )
    );
$body$;

REVOKE ALL ON FUNCTION public.can_view_reading_calendar(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_reading_calendar(uuid)
  TO authenticated;

-- Only the owner may see an ongoing session. Accepted followers can only
-- see finished sessions and only when not explicitly excluded.
DROP POLICY IF EXISTS "Readers can see only their own reading sessions"
  ON public.reading_sessions;
CREATE POLICY "Owner or eligible follower can read completed sessions"
  ON public.reading_sessions
  FOR SELECT TO authenticated
  USING (
    public.can_view_reading_calendar(profile_id)
    AND (profile_id = auth.uid() OR ended_at IS NOT NULL)
  );

-- Owner can restrict an accepted follower. No direct client mutations
-- to the exclusions table are allowed.
CREATE OR REPLACE FUNCTION public.set_reading_calendar_follower_hidden(
  p_follower_id uuid, p_hidden boolean
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  requester uuid := auth.uid();
BEGIN
  IF requester IS NULL OR p_follower_id IS NULL OR p_hidden IS NULL
     OR requester = p_follower_id
     OR NOT public.is_profile_active(requester) THEN
    RAISE EXCEPTION 'Not allowed' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM public.profiles WHERE id = requester FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account unavailable' USING ERRCODE = '42501';
  END IF;

  IF p_hidden THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.follows AS follow
      WHERE follow.follower_id = p_follower_id
        AND follow.following_id = requester
        AND follow.status = 'accepted'
    ) THEN
      RAISE EXCEPTION 'Follower not accepted' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.reading_calendar_hidden_followers(owner_id,follower_id)
    VALUES (requester,p_follower_id)
    ON CONFLICT (owner_id,follower_id) DO NOTHING;

    -- Existing calendar activity alerts must stop being visible immediately.
    DELETE FROM public.notifications
    WHERE recipient_id = p_follower_id
      AND actor_id = requester
      AND type = 'reading_session';
  ELSE
    DELETE FROM public.reading_calendar_hidden_followers
    WHERE owner_id = requester AND follower_id = p_follower_id;
  END IF;
  RETURN true;
END;
$body$;

REVOKE ALL ON FUNCTION public.set_reading_calendar_follower_hidden(uuid,boolean)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_reading_calendar_follower_hidden(uuid,boolean)
  TO authenticated;

-- Same three reaction types as book-review posts.
CREATE TABLE public.reading_session_reactions (
  reading_session_id uuid NOT NULL
    REFERENCES public.reading_sessions(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reaction_type text NOT NULL CHECK (reaction_type IN ('like','love','sad')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (reading_session_id, profile_id)
);
CREATE INDEX reading_session_reactions_session_idx
  ON public.reading_session_reactions(reading_session_id);
ALTER TABLE public.reading_session_reactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reading_session_reactions FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.reading_session_reactions
  TO authenticated;

CREATE POLICY "Visible calendar reactions"
  ON public.reading_session_reactions
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.reading_sessions AS session
    WHERE session.id = reading_session_id
      AND session.ended_at IS NOT NULL
      AND public.can_view_reading_calendar(session.profile_id)
  ));

CREATE POLICY "Readers react to permitted followers"
  ON public.reading_session_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    profile_id = auth.uid()
    AND public.is_profile_active(auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.reading_sessions AS session
      WHERE session.id = reading_session_id
        AND session.ended_at IS NOT NULL
        AND session.profile_id <> auth.uid()
        AND public.can_view_reading_calendar(session.profile_id)
    )
  );

CREATE POLICY "Readers change permitted reactions"
  ON public.reading_session_reactions
  FOR UPDATE TO authenticated
  USING (profile_id = auth.uid() AND public.is_profile_active(auth.uid()))
  WITH CHECK (
    profile_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.reading_sessions AS session
      WHERE session.id = reading_session_id
        AND session.ended_at IS NOT NULL
        AND session.profile_id <> auth.uid()
        AND public.can_view_reading_calendar(session.profile_id)
    )
  );

CREATE POLICY "Readers remove their own reactions"
  ON public.reading_session_reactions
  FOR DELETE TO authenticated
  USING (profile_id = auth.uid() AND public.is_profile_active(auth.uid()));

-- Keep all existing post/follow notifications intact.
ALTER TABLE public.notifications
  ADD COLUMN reading_session_id uuid
  REFERENCES public.reading_sessions(id) ON DELETE CASCADE;

CREATE INDEX notifications_reading_session_idx
  ON public.notifications(reading_session_id)
  WHERE reading_session_id IS NOT NULL;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IN (
      'reaction','want_to_read','want_to_read_completed','follow',
      'follow_request','reply','new_post',
      'reading_session','reading_reaction'
    )
  );

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_check1;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_check1 CHECK (
    (type IN ('reaction','want_to_read','want_to_read_completed','new_post')
      AND post_id IS NOT NULL AND reply_id IS NULL
      AND reading_session_id IS NULL)
    OR (type = 'reply'
      AND post_id IS NOT NULL AND reply_id IS NOT NULL
      AND reading_session_id IS NULL)
    OR (type IN ('follow','follow_request')
      AND post_id IS NULL AND reply_id IS NULL
      AND reading_session_id IS NULL)
    OR (type IN ('reading_session','reading_reaction')
      AND post_id IS NULL AND reply_id IS NULL
      AND reading_session_id IS NOT NULL)
  );

-- Hide old calendar updates after an unfollow or visibility exclusion,
-- including unread badge counts. Reaction alerts remain visible to the owner.
DROP POLICY IF EXISTS "Users can read their notifications"
  ON public.notifications;
CREATE POLICY "Users read only eligible notifications"
  ON public.notifications
  FOR SELECT TO authenticated
  USING (
    recipient_id = auth.uid()
    AND (
      type NOT IN ('reading_session','reading_reaction')
      OR (
        type = 'reading_session'
        AND EXISTS (
          SELECT 1 FROM public.reading_sessions AS session
          WHERE session.id = reading_session_id
            AND public.can_view_reading_calendar(session.profile_id)
        )
      )
      OR (
        type = 'reading_reaction'
        AND EXISTS (
          SELECT 1 FROM public.reading_sessions AS session
          WHERE session.id = reading_session_id
            AND session.profile_id = auth.uid()
        )
      )
    )
  );

-- Notify eligible accepted followers only after a timer finishes.
CREATE OR REPLACE FUNCTION public.notify_completed_reading_session()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
BEGIN
  IF OLD.ended_at IS NOT NULL OR NEW.ended_at IS NULL THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.notifications (
    recipient_id,actor_id,type,reading_session_id
  )
  SELECT follow.follower_id,NEW.profile_id,'reading_session',NEW.id
  FROM public.follows AS follow
  WHERE follow.following_id = NEW.profile_id
    AND follow.status = 'accepted'
    AND follow.follower_id <> NEW.profile_id
    AND NOT public.is_blocked_between(follow.follower_id,NEW.profile_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.reading_calendar_hidden_followers AS hidden
      WHERE hidden.owner_id = NEW.profile_id
        AND hidden.follower_id = follow.follower_id
    )
    AND public.is_profile_active(follow.follower_id);
  RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION public.notify_completed_reading_session()
  FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS reading_sessions_create_follower_notification
  ON public.reading_sessions;
CREATE TRIGGER reading_sessions_create_follower_notification
  AFTER UPDATE OF ended_at ON public.reading_sessions
  FOR EACH ROW EXECUTE FUNCTION public.notify_completed_reading_session();

CREATE OR REPLACE FUNCTION public.notify_reading_session_reaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  session_owner uuid;
BEGIN
  SELECT session.profile_id INTO session_owner
  FROM public.reading_sessions AS session
  WHERE session.id = NEW.reading_session_id;
  IF session_owner IS NOT NULL AND session_owner <> NEW.profile_id
     AND public.can_view_reading_calendar(session_owner) THEN
    INSERT INTO public.notifications (
      recipient_id,actor_id,type,reading_session_id
    ) VALUES (
      session_owner,NEW.profile_id,'reading_reaction',NEW.reading_session_id
    );
  END IF;
  RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION public.notify_reading_session_reaction()
  FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS reading_session_reaction_notification
  ON public.reading_session_reactions;
CREATE TRIGGER reading_session_reaction_notification
  AFTER INSERT ON public.reading_session_reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_reading_session_reaction();

-- Do not expose excluded followers via a separate public search endpoint.
