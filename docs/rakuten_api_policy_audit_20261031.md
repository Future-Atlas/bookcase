# Rakuten Web Service API — policy gap audit (2026-10-31)

**Status: partial engineering risk reduction; NOT a conclusion of compliance or a legal opinion.**
Baseline: `develop` 87f44a521783121eb9d8d76299a6da8e42142a30;
`main` 94e1cc434a0ae800227f32762295bbbcf0260afd.
The previous 2026-10-21 audit was made at an older main SHA and must not be
treated as an assessment of current production behavior.

## Primary sources

- [Rakuten Web Service terms (Japanese original governs)](https://webservice.rakuten.co.jp/guide/rule): articles 3, 8(4), 10(4), 10(7), 10(9), 13.
- [Books Book Search API](https://webservice.rakuten.co.jp/documentation/books-book-search): `itemUrl`, server-supplied `affiliateUrl` and catalog fields.
- [Official FAQ: API data usage purpose](https://webservice.faq.rakuten.net/hc/ja/articles/900001974363): promoting Rakuten products with links to their pages; prohibits unrelated copying/alteration.
- [Official FAQ: paid tools](https://webservice.faq.rakuten.net/hc/ja/articles/900001970826): affiliate-unrelated revenue from API use is restricted by Article 10(4).
- [Official FAQ: reuse/caching](https://webservice.faq.rakuten.net/hc/ja/articles/900001974343): price/availability cache generally up to 24 hours, other Rakuten IP generally up to 3 months; refreshing displayed price/availability at least weekly and showing retrieval time/disclaimer when not refreshing at least hourly.
- [Official FAQ: limits](https://webservice.faq.rakuten.net/hc/ja/articles/900001974383): at most 1 request/second **per application ID**.
- [Official FAQ: other services alongside Rakuten](https://webservice.faq.rakuten.net/hc/ja/articles/900001970786): identifies attribution and non-Rakuten affiliate linkage concerns.
- [Cloudflare: strict distributed limit requires Durable Objects](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/).
- [NDL metadata conditions](https://www.ndl.go.jp/data/data_service/quickguide) and [per-provider license rules](https://ndlsearch.ndl.go.jp/help/api/provider).
- [openBD data conditions](https://openbd.jp/terms/): promotional use only, respect changes/deletions; **not** an unrestricted archival alternative.

The precise interpretation of Rakuten terms for this SNS, and whether an
affiliate panel alongside Ninja AdMax is acceptable, requires direct guidance
from Rakuten and/or qualified counsel. Do not declare a violation from this
technical inventory.

## Audit: what can be stored and how it is used

| Source / storage | Current fields | Retention and visibility observed | Risk / proposed rule |
| --- | --- | --- | --- |
| `public.posts` | `book_id`, `book_title`, `book_author`, `book_publisher`, `book_description`, plus **user-authored** `comment`, `rating`, `is_spoiler` | Metadata snapshot inserted by `createPost` in `lib/services/supabase_service.dart`; no catalog-source provenance or expiry. Public reviews are exposed by RLS/SEO according to profile visibility and spoiler rules. | High: external descriptions/metadata may outlive permitted caching. Preserve original review/rating/book ID permanently; establish an independent metadata source and expiry for provider-owned fields. |
| `public.featured_books` | `book_id`, `book_title`, `book_author`, `book_publisher`, `book_cover_url`, `book_description` plus editorial `related_screen_titles`, priority and schedule | Stored by `adminSaveFeaturedBook` as a lasting snapshot; public active books read by Flutter and SEO pages. | High: images/descriptions can remain indefinitely and the SEO featured list currently does not provide item-level Rakuten links. Use curator-owned data/ISBN for long-lived entries; serve vendor metadata only when fresh and linked; migrate legacy snapshots without removing curated selection. |
| `public.collections`, `favorites`, `want_to_read` | Mainly `book_id` (+ user/timestamps) | Durable user-owned reading history, favorites, want-to-read relationships. Resolved for display by catalog APIs. | Lower: keep these **user-owned records** independent of Rakuten availability; verify every ID's provenance and avoid persisting Rakuten descriptions. |
| Client `RakutenApi._bookByIdCache` | Book including Rakuten metadata and price | Formerly unbounded lifetime per running app. | Mitigated in this PR: 15-minute TTL. |
| Cloudflare Worker proxy and SEO | Rakuten search/ISBN, prices, images, description, URLs | Per-IP request throttle was not a global application-ID control; SEO bypassed that throttle. | Mitigated in this PR for **each configured Worker environment** with a dedicated SQLite-backed Durable Object and 5-minute in-memory positive cache. |
| Book link UI | `Book.itemPrice`, purchase button, official `affiliateUrl` | Previously showed API price without a retrieval timestamp. | Mitigated in this PR: don't display price; retain validated affiliate link and advertising disclosure. |
| `/book/ISBN` and `/genre/*` crawler HTML | Rakuten description/image | Previously showed catalog data without item-level Rakuten merchant URL. | Mitigated in this PR: validate and show the genuine merchant URL beside API description, use the server-owned affiliate ID if configured; suppress unsupported description/cover/indexing when product URL is missing. Existing global Rakuten credit remains. |

**Not measured:** Actual database contents, provenance of already-persisted book
fields, historical age of rows, and whether third-party terms were accepted for
specific data providers. These require access-controlled DB inventory queries and
human review, not assumptions or silent data deletions.

## Quota coordination: limitations and rollout gate

- `cloudflare/rakuten-coordinator.mjs` admits only the two approved Rakuten
  book endpoints, verifies application ID/access key against Worker secrets,
  reserves the next outbound start at least **1,100 ms** away, persists
  reservations, caches successful responses for five minutes in memory, dedupes
  identical in-flight requests, bounds waiting requests, and honours upstream
  429 backoff. No raw credentials should be logged.
- Both `/api/rakuten` and SEO crawler paths receive the same coordinator in
  `cloudflare/worker.mjs`; the worker **fails closed** when the binding is absent.
- **Critical**: Wrangler environments have separate DO namespaces.
  Confirm that `staging` and `production` use **different Rakuten app IDs**.
  If they share an app ID, both environments and any other clients must route
  through ONE shared external quota service **before enabling the fix in
  production**. Merely matching class names does not share counters.
- Vercel's manual rollback/fallback path still calls Rakuten directly and does
  not participate in the global coordinator. **Do not activate an external
  fallback concurrently using the same app ID until it is routed through that
  same global service or its API use is explicitly disabled.**
- Before deploying changes to staging, validate Wrangler DO migration and
  secrets, smoke-test 200/429/503 behavior, and verify rate under concurrency.
  DOs have Free-plan allowances but actual account limits/billing must be checked.
- The app may temporarily show no search results under heavy load or Rakuten
  outages. Do not convert that into deletion of saved reviews, favorites, or
  reading history.

## Product and legal decisions still required — DO NOT close the Asana task yet

1. **Persistent metadata provenance and expiry.** Separate book identity
   (`ISBN`/provider-independent metadata) from Rakuten-only catalog fields.
   Design provider, fetched_at, expires_at, deletion-request flags and a
   verified cleanup workflow. Review and migrate existing `posts` and
   `featured_books` snapshots without deleting user-authored reviews,
   ratings, reading records or curated book IDs. Server and Flutter must ignore
   expired snapshots and re-fetch permitted data as needed.
2. **Editorial featured book metadata.** Replace indefinite cover/description
   copies with licensed independent bibliographic data or a short-lived Rakuten
   cache linked to an actual product. Design corresponding Flutter + crawler
   fallback to ISBN, editorial text and reviews when catalog API is unavailable.
3. **Commercial model.** Ask Rakuten whether API-powered pages can coexist
   with Ninja AdMax advertising and future paid subscriptions; avoid assuming
   that non-Rakuten advertising is automatically allowed. Separate revenue
   attribution and product-introduction surfaces if required.
4. **Global quota secret inventory.** Privately confirm all deployments and
   jobs using the same Rakuten application ID, including Vercel fallback.
   No secret values belong in issues or audit documents.
5. **Independent catalog source.** NDL-created bibliographic metadata can be
   used commercially subject to terms, but third-party supplied metadata has
   individual provider conditions. Map allowed fields and licensing before
   introducing a permanent book-identity table. openBD is **not** unrestricted
   public-domain book data.
6. **Operator acceptance.** Confirm Rakuten's written guidance, review
   implementation changes, merge to `develop`, validate staging and
   app behavior, then request explicit approval before any `main` PR/merge
   or production release. Keep the existing affiliate action and user data.

## Acceptance checklist for this first PR

- [x] Official terms/FAQ compared and dated; no violation claimed.
- [x] Current DB/API/UI retention and use inventory documented.
- [x] Remove untimestamped price from the Rakuten purchase action.
- [x] Expire frontend cache; bound Worker cache; dedupe and centralize per-env quota.
- [x] Validate merchant URLs and add them to crawled catalog content.
- [ ] Historical persistence/source migration, provider-specific licensing.
- [ ] Same-app-ID staging/production and alternate-host quota reconciliation.
- [ ] Rakuten response on Ninja AdMax / other commercial use.
- [ ] Staging tests and PR CI complete.
- [ ] Explicitly approved production release.
