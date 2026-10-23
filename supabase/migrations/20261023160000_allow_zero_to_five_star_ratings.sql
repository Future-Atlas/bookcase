-- Preserve historic rating values while permitting the full 0.0-5.0 scale.
-- The Flutter application snaps newly submitted ratings to tenths.
ALTER TABLE public.posts
  DROP CONSTRAINT IF EXISTS posts_rating_check;

ALTER TABLE public.posts
  ADD CONSTRAINT posts_rating_check
  CHECK (rating >= 0.0 AND rating <= 5.0);
