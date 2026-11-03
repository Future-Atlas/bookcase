# Staging-only Rakuten Books catalogue restoration (2026-11-03)

## Scope

- `develop` **staging Flutter build only** compiles
  `--dart-define=STAGING_RAKUTEN_CATALOG=true`. Other builds retain the
  existing NDL/Open Library/openBD acquisition flows.
- Book discovery sections (`新着`, `和書`, `洋書`, `ベストセラー`) and
  search switch to the Rakuten Books Book/ForeignBook Search APIs through
  same-origin `/api/rakuten`. The original app sections, social activity,
  Supabase schema and user data are **not** changed.
- The staging book-detail, post-book, user-shelf, and featured-book metadata
  lookup paths also use the production-style Rakuten ISBN resolver, via
  `BookCatalogLookup`. Non-staging builds keep their old NDL/openBD resolver.
  A Rakuten error does **not** silently fall back to NDL in staging.
  Only exact ISBN matches can enrich stored book records; unapproved retailer
  image URLs are discarded before rendering or replacing a stored cover.
- The Worker allows `/api/rakuten` only with `APP_ENV=staging`. It remains
  HTTP 410 on production or any unnamed environment.
- `RAKUTEN_APP_ID` and `RAKUTEN_ACCESS_KEY` stay only in the staging
  Worker environment. Never put them in Flutter --dart-define or the browser.
- The proxy accepts only fixed Rakuten book endpoints, a small set of
  validated query fields, and at most 30 books per request.
- The existing `RAKUTEN_QUOTA` Durable Object globally serializes requests
  per Rakuten app ID (~1 request/1.1 seconds), coalesces identical in-flight
  calls, and temporarily caches success. The Cloudflare general API limiter
  (120 per IP/minute) **plus catalog limiter** (24 per IP/minute) apply.
  Failed API calls are not cached.
- Flutter requests up to **27** books once, keeps all eligible books in
  memory, and reuses nine books at a time for the horizontal pager.
  Previously displayed pages are reused without network calls.
- `和書` maps to Rakuten's ordinary `001` book category, not the literal
  keyword "和書". Foreign books use the `005` foreign-book category.
  **Important limitation:** Rakuten book category metadata is not
  edition-level evidence of book language. This temporary staging mode
  does *not* provide the prior strict `jpn` or `eng` language guarantee.
- Search also uses Rakuten (title/author/publisher field priorities) in
  staging. Existing `BookRepository` NDL injection tests remain unchanged.
- No automatic cover-image rights fallback is re-enabled. The
  `BookCoverImage` component continues to show only openBD/approved
  publisher covers; retailer thumbnails and `images.weserv.nl` are not
  displayed. ISBN/user-created content is not bulk-stored or migrated.

## Provider app registration prerequisite

At 2026-11-03 08:12 JST, and again after the hostname fix at 12:24 JST,
the deployed stage probes returned HTTP 502 from
Sharemarium, with **upstream HTTP 403 from Rakuten** for both book and foreign
book search. These are not Cloudflare 429s. The actual origin/referer in this
Worker is now `https://sharemarium-staging.sharemarium.workers.dev/` (not
`https://staging.sharemarium.com/`). Before re-testing, the operator should
check the Rakuten Web Service app dashboard
https://webservice.rakuten.co.jp/app/list for:

1. A valid and matching `RAKUTEN_APP_ID` and `RAKUTEN_ACCESS_KEY` for
   the staging Worker (never put either value in Flutter or GitHub logs).
2. The active staging hostname in the app's allowed websites / referrers.
3. API access scopes including the Rakuten Books Book / ForeignBook APIs.

A 403 alone cannot distinguish credential, site-allowlist and scope denial.
The app dashboard must be verified; code cannot override provider controls.
Do not falsify the Referer using production's hostname or bypass security.

## Availability and commerce limitations

The service provider's book-search documentation requires application ID
and access key and limits individual requests to 30 items. It warns that
repeated identical URL requests may be temporarily throttled. The staging
quota and 27-item buffering avoid excessive requests.

Official API docs:
- https://webservice.rakuten.co.jp/documentation/books-book-search
- https://webservice.rakuten.co.jp/documentation/books-foreign-search

**Terms need operator approval before a commercial production switch.**
Rakuten says API information is for introducing items with links to the
relevant Rakuten product pages, and its published guidance restricts
revenue derived from API use outside Rakuten Affiliate. Sharemarium has
subscription features. Do not treat this technical staging restoration as
legal permission for subscription-supported production use:
- https://webservice.faq.rakuten.net/hc/ja/articles/900001974363
- https://webservice.faq.rakuten.net/hc/ja/articles/900001970826

## QA / Rollback

1. Pull-request CI/CodeQL/Cloudflare checks must pass.
2. Deploy only to `sharemarium-staging` using the existing `develop`
   GitHub Actions workflow and already configured staging secrets.
3. Verify `/api/rakuten?endpoint=book&booksGenreId=001&hits=3&page=1`
   and `endpoint=foreign&booksGenreId=005` return HTTP 200 where permitted.
   The deploy job's read-only probe prints status, count, and elapsed time,
   never credentials or raw data.
4. Confirm `和書`, `洋書`, `新着`, `ベストセラー`, keyword search,
   next/previous buttons, and content safety on the Flutter staging UI.
   Provider 429/503 may be transient; do not stress-test Rakuten.
5. Rollback: remove the staging build flag and redeploy `develop`.
   API-only NDL/Open Library code remains intact.

**No `main` code, production Worker, Supabase data or billing settings are
changed by this branch.**
