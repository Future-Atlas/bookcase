BEGIN;
SELECT no_plan();

SELECT has_column('public','posts','book_metadata_source','posts record book metadata provenance');
SELECT has_column('public','posts','book_metadata_observed_at','posts record the observed catalog timestamp');
SELECT has_column('public','featured_books','book_metadata_source','featured books record book metadata provenance');
SELECT has_column('public','featured_books','book_metadata_observed_at','featured books record catalog observation');

SELECT ok(
  (SELECT count(*) = 2
   FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name IN ('posts','featured_books')
     AND column_name = 'book_metadata_source'
     AND column_default LIKE '%unverified%'),
  'existing rows default to unverified; no false claim of Rakuten licensing or source'
);

SELECT ok(
  (SELECT count(*) = 2
   FROM pg_constraint
   WHERE conname IN ('posts_book_metadata_source_allowed',
                     'featured_books_metadata_source_allowed')),
  'provider-source values are checked in both tables'
);

SELECT * FROM finish();
ROLLBACK;
