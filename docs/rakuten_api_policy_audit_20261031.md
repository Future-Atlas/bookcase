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
| `public.posts` | `book_id`, `book_title`, `book_author`, `book_publisher`, legacy `book_description`, **user-authored** `comment`, `rating`, `is_spoiler`; new `book_metadata_source`/`book_metadata_observed_at` | The new additive migration marks all legacy rows `unverified`, leaves their content untouched, and records the source/timestamp of newly selected books. Newly created posts store an empty API description; reviews remain readable without Rakuten through ISBN-only SEO fallback. | Legacy titles/authors/descriptions have **unresolved** origin and expiry. Never bulk-delete user reviews, ratings or book IDs; establish provenance/rights before remediating old metadata. |
| `public.featured_books` | ISBN/title/author/publisher, legacy `book_cover_url` and `book_description`, editorial `related_screen_titles`, schedule/priority and new source/timestamp fields | **No new provider cover/description snapshots**: save empty strings in those fields. Flutter ignores undated legacy cover/description snapshots and fetches fresh artwork/synopsis transiently; on API failure, curated book cards and ISBN remain. Crawler featured lists show curated titles without unverified legacy cover/description. | **Remaining risk:** old descriptions/covers still exist in DB awaiting rights/retention review, and stored title/author may still be provider-sourced. Avoid pretending this has resolved the commercial licensing question. |
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
- Legacy Vercel/serverless entrypoints **fail closed (503)** for Rakuten API
  requests without Cloudflare's bound coordinator. This prevents quota bypass,
  but *book search will not work* in a Vercel-only fallback until it forwards
  through an approved shared quota service. Public original book reviews remain
  accessible using their ISBN even when Rakuten itself is unavailable.
  Never set a bypass flag or restore uncoordinated requests to work around this.
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
5. **Independent catalog source.** NDL Search's official API usage guide
   explicitly treats even an individual site earning **advertising revenue** as
   commercial use: a usage application/permission is normally required, except
   for provider records pre-authorized for all purposes (e.g. applicable CC0/PDM
   sources). Filter by the data-provider rights table; `open` covers explicitly
   open PDM/CC0 metadata. Never assume NDL-wide or openBD data is commercially
   reusable without reviewing the individual terms and rights.
6. **Operator acceptance.** Confirm Rakuten's written guidance, review
   implementation changes, merge to `develop`, validate staging and
   app behavior, then request explicit approval before any `main` PR/merge
   or production release. Keep the existing affiliate action and user data.

## Access-controlled database inventory (counts only)

Run these **read-only** queries in the authorized Supabase SQL editor, after
the additive migration has been applied to staging. No personal reviews,
usernames, secrets, or raw book metadata should be pasted in PRs:

```sql
SELECT book_metadata_source,
       COUNT(*) AS rows,
       COUNT(*) FILTER (WHERE book_description <> '') AS rows_with_legacy_description,
       COUNT(*) FILTER (WHERE book_metadata_observed_at IS NULL) AS unverified_capture_time,
       MIN(created_at) AS earliest_post,
       MAX(created_at) AS latest_post
FROM public.posts
GROUP BY book_metadata_source
ORDER BY book_metadata_source;

SELECT book_metadata_source,
       COUNT(*) AS rows,
       COUNT(*) FILTER (WHERE book_cover_url <> '') AS rows_with_legacy_cover,
       COUNT(*) FILTER (WHERE book_description <> '') AS rows_with_legacy_description,
       COUNT(*) FILTER (WHERE book_metadata_observed_at IS NULL) AS unverified_capture_time,
       MIN(created_at) AS earliest_curated,
       MAX(updated_at) AS last_curated_update
FROM public.featured_books
GROUP BY book_metadata_source
ORDER BY book_metadata_source;
```

**Do not mass-clear historical data without a reviewed migration and backup.**
The additive provenance columns distinguish newly tagged records from
unverified historical snapshots; they are **not** proof of licensing or
permission to retain provider information indefinitely.

### Deployment gates

- The feature branch remains a **draft PR**. Staging DB migration is additive;
  do not touch production data in this PR.
- Check all GitHub environment/Cloudflare/Vercel consumers of the Rakuten
  application ID **without printing secret values**. One quota coordinator
  per Worker environment does not enforce 1 request/second when the same ID is
  shared across deployments. The release must be blocked until IDs are
  distinct or all environments use one genuine shared coordinator.
- Separately confirm Cloudflare's Durable Object SQLite Free-plan limits,
  network error behavior and the operator's intended fallback procedures.
- Official permission regarding Rakuten API pages coexisting with Ninja AdMax
  remains **unconfirmed**; a legal/business decision is still needed.
- Before deployment, verify that frontend book search, curated books, post
  submission, public reviews and all user bookshelf lists work on staging,
  including simulated upstream 429/unavailability.

## Acceptance checklist for this first PR

- [x] Official terms/FAQ compared and dated; no violation claimed.
- [x] Current DB/API/UI retention and use inventory documented.
- [x] Remove untimestamped price from the Rakuten purchase action.
- [x] Expire frontend cache; bound Worker cache; dedupe and centralize per-env quota.
- [x] Stop copying vendor description into new permanent post rows while retaining comments and ISBN.
- [x] Stop creating permanent featured-book cover/description snapshots; hide unverified legacy content and use short-lived on-demand metadata.
- [x] Keep substantive original public reviews visible even during upstream outages using ISBN-only fallback.
- [x] Track explicit source/timestamps for new post and featured metadata; legacy rows default to `unverified`.
- [x] Fail closed on legacy Vercel direct API paths to prevent quota bypass.
- [x] Validate merchant URLs and add them to crawled catalog content.
- [ ] Historical metadata rights review, retention/cleanup migration and independent-source licensing.
- [ ] Same-app-ID staging/production and alternate-host quota reconciliation.
- [ ] Rakuten response on Ninja AdMax / other commercial use.
- [ ] Staging tests and PR CI complete.
- [ ] Explicitly approved production release.
