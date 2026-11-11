-- Risk inventory: distinguish the provenance of catalog-derived labels from
-- user-owned reviews / ratings and from ISBN identifiers.
-- This is additive and does NOT delete or rewrite pre-existing book snapshots.
-- All legacy rows remain 'unverified' with no observed timestamp until a
-- separate, evidence-based migration plan is reviewed.
ALTER TABLE public.posts
    ADD COLUMN IF NOT EXISTS book_metadata_source TEXT NOT NULL DEFAULT 'unverified',
    ADD COLUMN IF NOT EXISTS book_metadata_observed_at TIMESTAMPTZ;
ALTER TABLE public.featured_books
    ADD COLUMN IF NOT EXISTS book_metadata_source TEXT NOT NULL DEFAULT 'unverified',
    ADD COLUMN IF NOT EXISTS book_metadata_observed_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'posts_book_metadata_source_allowed'
      AND conrelid = 'public.posts'::regclass
  ) THEN
    ALTER TABLE public.posts ADD CONSTRAINT posts_book_metadata_source_allowed
      CHECK (book_metadata_source IN ('unverified','rakuten','ndl','editorial'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'featured_books_metadata_source_allowed'
      AND conrelid = 'public.featured_books'::regclass
  ) THEN
    ALTER TABLE public.featured_books
      ADD CONSTRAINT featured_books_metadata_source_allowed
      CHECK (book_metadata_source IN ('unverified','rakuten','ndl','editorial'));
  END IF;
END
$$;

COMMENT ON COLUMN public.posts.book_metadata_source IS
  'Origin of selected book labels at creation, not of the independent user review. Legacy rows are unverified.';
COMMENT ON COLUMN public.posts.book_metadata_observed_at IS
  'Client-observed capture time; informational only. It does not grant retention rights.';
COMMENT ON COLUMN public.featured_books.book_metadata_source IS
  'Original source of curated book labels. Covers and descriptions are no longer saved from API responses.';
COMMENT ON COLUMN public.featured_books.book_metadata_observed_at IS
  'Client-observed capture time; informational only. This is NOT a valid cache expiration guarantee.';
