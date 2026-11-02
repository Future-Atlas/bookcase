> **Historical document — superseded for cover rights on 2026-11-02.**
> Google Books and Open Library automatic cover fallbacks described below are
> **disabled**. See [commercial book cover policy](commercial_book_cover_policy_20261102.md).
> Do not restore the older fallback logic without approved commercial licenses.

# NDL + openBD migration (PR #194, draft)

## Intent and boundaries

Replace Rakuten Web Service catalog calls with National Diet Library Search as the primary source and openBD as optional enrichment. Keep all user-authored posts, shelves, favorites, reactions and ISBN-based links intact. The legacy `/api/rakuten` responds with 410 and no longer contacts Rakuten.

### Functional mapping

- Home/new arrivals: preserve the legacy **27 candidates per 9 displayed books**. Because a broad one-year publication-date scan timed out in staging, prefer the official **new-bibliography (in-process)** provider for the **last 90 days**, with completed national bibliography as a fallback when a source is empty or unavailable. Stop scanning a source after a wholly unusable window instead of needlessly requesting `idx=28`. Keep raw offsets, buffer unused eligible ISBNs and enforce a 4-window-per-visible-page budget. Sort each retrieved window by publication date (not a verified global release-date ranking). This is a performance mitigation; NDL publication-date filtering is still not Rakuten's release-day sort.
- Home Japanese books (revised 2026-11-02): show a separate `和書` carousel directly after `新着`. Query the existing national bibliography with **explicit title terms** (`日本`, `物語`, `文学`); accept only sole `jpn`/`ja` language tags. Give it independent cursors, pagination, retry and direct `/genre/japanese` route; this is a discovery sample, not all Japanese books.
- Home English books (revised 2026-11-02): use `ndl-boj` with explicit `title=Japan` / `title=Tokyo` and then holdings with similarly bounded titles. The previous **provider-only `ndl-boj`** request reached the 18-second proxy timeout and returned `504 ndl_timeout`; the proxy now rejects all missing-search queries. Require explicit, sole `eng`; exclude Chinese, Korean, other languages, `en`/`english` aliases, missing tags and mixed `jpn eng` even from the foreign-language provider. Deduplicate ISBNs and preserve page cursors. These fixed title searches are narrow examples and **not complete global English-language coverage**; 504 can still occur if NDL is slow.
- Home popular: ranked by the frequency of eligible, public, non-age-restricted Sharemarium review posts (most recent 300 records). This is **internal community popularity**, not the external Rakuten bestseller ranking. If no eligible reviews exist, the section may be empty. The existing visible label is `人気作品`.
- Keyword search: title/author/publisher priority and existing exact-match ranking remain. A field-cursor keeps unused raw page items, tracks 1-based NDL offsets, deduplicates by ISBN and carries an explicit `hasMore` flag (not inferred from the number of visible cards). The UI still allocates 10/5/5 per 20 results when data is available. Empty fields fall back to other fields, and a national-bibliography source may fall back to in-process source. NDL and Rakuten search inventories remain different.
- Cover and descriptions: openBD enriches all ISBN-13 results in batches of 25, preserving missing items and handling absent/replaced records without discarding user data. Image availability and rights must be checked in staging.
- Safety: existing keyword checks and the ONIX adult audience codes `01`/`02`/`03` are treated as restricted. Warning-only codes `04`/`05`/`06`/`07` do not alone establish 18+ status. **Product decision 2026-10-31:** books with unknown age classification remain visible unless other adult indicators match; verify misses during staging. Public SEO excludes recognized adult terms and flagged posts; API-level anonymous age-aware restriction remains a separate security review.
- Purchase links: Rakuten affiliate **API** is retired; manually verified links may be attached to ISBNs in `lib/config/rakuten_affiliate_links.dart`. A missing verified product link hides the purchase button; no ISBN-to-Rakuten-product link is invented.

### Unresolved prerequisites before release

1. **NDL rights/application**: NDL states that revenue-bearing sites (including advertising) are commercial use; verify that the exact national/new-arrival provider records are covered by advance authorization and implement the requested attribution. For continual API usage, notify the NDL about the service and expected traffic. See https://ndlsearch.ndl.go.jp/help/api and https://www.ndl.go.jp/data/data_service/jnb .
2. **openBD rights and safety data**: Confirm whether the actual current production records contain usable ONIX ratings and what cover image redistribution/hotlink restrictions apply. Check 100-300 ISBNs including manga, Japanese novels, business books, foreign titles and known restricted publications. No adult flag does not prove safety; our agreed interim product policy is nevertheless to **show unknown records**, with safeguards for confirmed adult matches.
3. **Affiliate compliance**: Confirm Sharemarium's website/user-generated-content placement with Rakuten Affiliate separately. Collect official product-level affiliate URLs; no automatic complete ISBN mapping is possible without a legitimate permitted source.
4. **Publishing order**: Update credits and content policies, sample staging search genres and age groups, SEO direct paths, ad scripts, cached featured book data and legacy provenance migration. Do not deploy automatically.
5. **Historical data**: Run the existing provenance inventory. Do not delete old metadata or user posts until source licensing and retention decisions are reviewed.
6. **Search quality**: Run `docs/ndl_openbd_stage_checklist.md` on staging; compare old/new search for title/author/publisher, 10/5/5 placement, multi-page uniqueness, new-arrivals, NDC genres, foreign-language coverage, 18+ behavior and cover availability. Do not declare parity until the samples pass.
7. **Infrastructure**: Since this branch no longer uses the Rakuten DO coordinator, remove old Durable Object bindings in a *separately reviewed* infrastructure cleanup only after migration validation.

## Rollback and verification

Past migration PR #194 is merged into `develop`. A separate home-feed candidate-refill PR should remain draft until CI is green. Staging deploys automatically when an approved PR is merged into `develop`. CI checks validate syntax and unit assumptions but do not substitute for permitted real-service traffic or staging. No production keys are required for the NDL/openBD public endpoints; Supabase staging credentials are required for integration QA.

### Staging new-arrivals timeout recovery (2026-11-01)

The Cloudflare NDL proxy previously aborted upstream searches at 12s and returned `502 ndl_unavailable`; Flutter silently converted these to `NdlSearchBatch([], hasMore:false)`, permanently exhausting the home cursor. The proxy now caps NDL calls at 18s and returns `504 ndl_timeout` for aborts, `503` for upstream 429/503 and `502` for other upstream failures, with no-store on failures. The Flutter client allows 22s and marks 429/5xx/transport errors as temporary; the home feed never increments its offset for such failures. A successful fallback source can still fill the visible cards. If the source remains unavailable, the empty 新着/洋書 panel exposes an explicit **もう一度取得する** action to reset that section only; no automatic storm of retries is initiated. Raw-error responses are never displayed as books.

NDL documents that performance varies with query conditions and imposes access-concurrency limits. The 90-day date filter and bounded additional windows reduce search load, but do not guarantee NDL uptime or 9 eligible ISBNs. Recheck actual staging responses and age filtering before considering production deployment. The long-term option for a true newly-registered bibliography stream is a separately designed scheduled, rights-compliant OAI-PMH ingestion/cache, not an unbounded search-page walk.


### New-arrivals ISBN parsing defect (2026-11-01)

The public NDL OpenSearch response and DC-NDL documentation include hyphenated ISBN identifiers (for example `978-4-297-13633-8`). The client previously used a regex matching only contiguous 10/13-digit sequences, silently dropping valid records **after a successful 200 RSS response**. Increasing request timeouts and reducing the publication date window cannot fix that. The parser now normalizes ISBN hyphens/spacing before validating the 10/13-digit ISBN representation and refuses to promote arbitrary NDL IDs/URLs. The home query now prioritizes the dedicated `iss-ndl-opac-inprocess` provider again; the PR #199 national-first workaround was necessary only while the ISBN parser was dropping hyphenated records. OAI-PMH `set=iss-ndl-opac-inprocess` is a separately supported source of recent *catalogue updates*; a live probe on 2026-11-01 timed out after 22 seconds, so do not replace the home feed with a live per-view OAI-PMH query without a controlled ingestion/cache design. Current release fix focuses on returning valid ISBNs from the existing official feed.



### Cover-image display and rights (2026-11-01)

The stage and direct openBD API both returned HTTP 200 for ISBNs
`9784488402327` (new 2026 Japanese novel), `9784413299084` (2026 non-fiction) and
`9784101010014`, but each response had **no `summary.cover`**.
NDL OpenSearch returns bibliographic records, not a usable cover URL;
NDL's original cover API was discontinued on 2026-03-31. Absence of covers
is **not a failure of the NDL ISBN parser or an openBD 502**.

The shared `BookCoverImage` widget first uses the verified existing
`Book.coverUrl` (e.g. openBD). For missing images, `OpenBdApi.enrich` calls
the same-origin `/api/book-covers` proxy in batches of at most 25 ISBNs.
The Worker requests Google's **keyless Dynamic Links** endpoint via the
published `bibkeys=ISBN:...` interface and parses its JSONP strictly as
JSON (never evaluates it). Google Books' ordinary REST API returned 429,
but Dynamic Links returned actual thumbnail and `info_url` fields for
both recent Japanese ISBNs in a live probe. Only exact requested ISBN
keys, allowed Google hosts and results with a valid Google Books info-page
link are accepted. The UI stores the source plus credit link in memory and
displays a clickable **Google ブックス** badge on these thumbnails, and
credits the source in `CatalogCredit`. No Google image bytes are copied
or rehosted; successful proxy metadata is only edge-cached for five minutes.
Google Books Dynamic Links' viewability varies by location, so we do not
make preview/viewability claims based on this server-side thumbnail lookup.

When Google has no image or the API fails, the UI requests the same ISBN at
`https://covers.openlibrary.org/b/isbn/{isbn}-M.jpg?default=false`.
Open Library explicitly permits displaying its cover URLs on public pages;
the `default=false` switch ensures nonexistent covers produce HTTP 404
instead of blank white images. No unlicensed book cover scraping, image
downloads, permanent caching, rehosting or title-based guessed matches.
Open Library limits non-ID/OLID requests to 100 per IP per 5 minutes:
do not crawl or prefetch the entire catalogue.

On Flutter Web, a cross-origin cover CDN without CORS may not work with
`Image.network` default settings. Google Books thumbnails are shown only
with explicit Google credit and an outbound information-page link. Use
`WebHtmlElementStrategy.fallback` for original cover URLs and
`WebHtmlElementStrategy.prefer` for Open Library image URLs to allow browser
HTML image loading. If neither source has a cover, show the title and
**表紙画像なし**; never invent an actual cover.

**Important limitation:** Open Library returned 404 for the two live-tested
recent Japanese titles, but Google Books Dynamic Links returned thumbnail
URLs. A thumbnail URL does not guarantee that an image can be loaded in every
browser or territory; the image fallback continues to show `表紙画像なし`
when neither provider supplies a usable jacket. Complete Japanese edition
coverage still requires publisher/JPRO-authorized sources, separately reviewed
for commercial usage and image licensing.
