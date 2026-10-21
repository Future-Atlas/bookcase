-- This legacy RPC accepted an arbitrary profile UUID and ran with the
-- function owner's privileges. The application no longer calls it, so remove
-- the exposed mutation surface instead of trying to preserve unsafe behavior.
DROP FUNCTION IF EXISTS public.increment_read_count(UUID);
