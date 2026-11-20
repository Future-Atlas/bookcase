-- A user's "want to read" action is a BOOK state, regardless of which
-- surface was tapped. Keep post_want_to_reads only for notification attribution.
-- An existing (profile_id, book_id) PK makes every user count at most once.

CREATE OR REPLACE FUNCTION public.toggle_want_to_read(
    target_book_id TEXT,
    target_book_title TEXT DEFAULT '',
    target_book_author TEXT DEFAULT '',
    target_book_cover_url TEXT DEFAULT '',
    source_post_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    actor UUID := (SELECT auth.uid());
    target_post public.posts%ROWTYPE;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Authentication required';
    END IF;
    IF NOT public.is_profile_active(actor) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Account is not active';
    END IF;
    IF NOT public.current_user_can_use_want_to_read() THEN
        RETURN 'subscription_required';
    END IF;

    target_book_id := btrim(COALESCE(target_book_id, ''));
    IF target_book_id = '' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Book ID is required';
    END IF;

    -- Validate a post-sourced tap before altering the single book state.
    -- Never accept a mismatched, invisible, age-ineligible or own post.
    IF source_post_id IS NOT NULL THEN
        SELECT * INTO target_post FROM public.posts WHERE id = source_post_id;
        IF NOT FOUND
           OR target_post.book_id <> target_book_id
           OR NOT public.can_view_profile_content(target_post.profile_id)
           OR (target_post.is_age_restricted
               AND NOT public.current_user_can_view_age_restricted()) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Post is not available';
        END IF;
        IF target_post.profile_id = actor THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Cannot react to your own post';
        END IF;
    END IF;

    -- Serialize two near-simultaneous taps of the same book by one account.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext(actor::TEXT),
        pg_catalog.hashtext(target_book_id)
    );

    -- Tapping either button OFF clears the book-level state. Per-post rows
    -- are notification attributions, never separate active selections.
    IF EXISTS (
        SELECT 1 FROM public.want_to_read_books
        WHERE profile_id = actor AND book_id = target_book_id
    ) THEN
        DELETE FROM public.post_want_to_reads AS engagement
        USING public.posts AS source
        WHERE engagement.post_id = source.id
          AND engagement.profile_id = actor
          AND source.book_id = target_book_id;

        DELETE FROM public.want_to_read_books
        WHERE profile_id = actor AND book_id = target_book_id;
        RETURN 'removed';
    END IF;

    -- Preserve the existing invariant: read books cannot be on the shelf.
    IF EXISTS (
        SELECT 1 FROM public.posts
        WHERE profile_id = actor AND book_id = target_book_id
    ) OR EXISTS (
        SELECT 1 FROM public.collections
        WHERE profile_id = actor AND book_id = target_book_id AND status = 'read'
    ) THEN
        RETURN 'already_read';
    END IF;

    INSERT INTO public.want_to_read_books (
        profile_id, book_id, book_title, book_author, book_cover_url,
        saved_directly, updated_at
    ) VALUES (
        actor, target_book_id,
        left(COALESCE(NULLIF(target_book_title, ''), target_post.book_title, ''), 500),
        left(COALESCE(NULLIF(target_book_author, ''), target_post.book_author, ''), 500),
        left(COALESCE(target_book_cover_url, ''), 2000),
        source_post_id IS NULL, timezone('utc'::text, now())
    ) ON CONFLICT (profile_id, book_id) DO UPDATE
    SET book_title = CASE WHEN EXCLUDED.book_title = '' THEN want_to_read_books.book_title ELSE EXCLUDED.book_title END,
        book_author = CASE WHEN EXCLUDED.book_author = '' THEN want_to_read_books.book_author ELSE EXCLUDED.book_author END,
        book_cover_url = CASE WHEN EXCLUDED.book_cover_url = '' THEN want_to_read_books.book_cover_url ELSE EXCLUDED.book_cover_url END,
        saved_directly = EXCLUDED.saved_directly,
        updated_at = timezone('utc'::text, now());

    -- Only post-originated taps create a post-owner notification.
    -- Book-page taps do not notify every author of this book.
    IF source_post_id IS NOT NULL THEN
        INSERT INTO public.post_want_to_reads (post_id, profile_id)
        VALUES (source_post_id, actor)
        ON CONFLICT (post_id, profile_id) DO NOTHING;
    END IF;
    RETURN 'added';
END;
$function$;

REVOKE ALL ON FUNCTION public.toggle_want_to_read(TEXT, TEXT, TEXT, TEXT, UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_want_to_read(TEXT, TEXT, TEXT, TEXT, UUID)
    TO authenticated;

-- Efficient, privacy-aware totals and selection status for post batches.
-- SECURITY INVOKER deliberately keeps existing RLS on want_to_read_books.
CREATE OR REPLACE FUNCTION public.get_book_want_to_read_states(
    target_book_ids TEXT[]
)
RETURNS TABLE (
    book_id TEXT,
    want_to_read_count BIGINT,
    wanted_by_current_user BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
    SELECT wanted.book_id,
           count(DISTINCT wanted.profile_id)::BIGINT,
           COALESCE(bool_or(wanted.profile_id = (SELECT auth.uid())), FALSE)
    FROM public.want_to_read_books AS wanted
    WHERE wanted.book_id = ANY(COALESCE(target_book_ids, ARRAY[]::TEXT[]))
    GROUP BY wanted.book_id;
$function$;

REVOKE ALL ON FUNCTION public.get_book_want_to_read_states(TEXT[])
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_book_want_to_read_states(TEXT[])
    TO anon, authenticated;

COMMENT ON FUNCTION public.get_book_want_to_read_states(TEXT[]) IS
    'Book-level unique visible want-to-read users and current user selection, respecting shelf RLS.';
