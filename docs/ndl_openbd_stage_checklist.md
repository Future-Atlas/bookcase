# Sharemarium NDL/openBD staging QA (PR #194)

This checklist is a verification gate, not permission to deploy. Keep PR as draft and do not merge while CI fails.

## CI gate
- GitHub Actions CI: Flutter analyze, unit tests, Web build, Node API tests pass.
- Cloudflare Workers, Supabase Migrations and CodeQL checks pass.
- Verify staging SHA matches reviewed PR head only after deployment is authorized.

## Search equivalence corpus
Compare ISBNs, order and screenshots for 20-30 old/new searches:
- Titles: コンビニ人間, ノルウェイの森.
- Normalization: プロジェクト・ヘイル・メアリー and プロジェクトヘイルメアリー.
- Authors: 村上春樹, アンディ・ウィアー, Andy Weir.
- Publishers: 講談社, 早川書房, Kodansha Co.
- Japanese and English titles, manga, business books, ISBNs missing covers/openBD records.
- Confirm exact-match top ranking, 10/5/5 placement if enough candidates, ISBN uniqueness through pages 1-3, and correct Load More behavior with raw NDL duplicate/ISBN-less slots.

## Home sections
- 新着: when fewer than nine usable records appear in one 27-item raw NDL window, verify next-window refill and source fallback; each page must preserve any unused ISBNs and never repeat across pages. Compare publication dates with publishers: NDL in-process is not publication-day inventory.
- 人気作品: the new metric is eligible public Sharemarium post counts, not Rakuten's external bestseller ranking.
- 和書: homepage order is `人気作品 → 新着 → 和書 → 洋書`. Fetch national-bibliography records with a bounded title search and show only records with an explicit **sole `jpn` or `ja`** language tag. Confirm pages 1-2 have no repeated ISBNs, the retry button works and the route `/genre/japanese` shows this section alone. Missing/foreign/bilingual language metadata must not be treated as Japanese from the title alone.
- 洋書（英語のみ）: `ndl-boj` and holdings requests MUST include a restrictive title query (e.g., `title=Japan` or `title=Tokyo`). Provider-only `?dpid=ndl-boj&mediatype=books` previously caused 18-second `504 ndl_timeout` responses; the proxy now rejects it with `400 missing_catalog_search`. Check only records with exactly `dc:language=eng` appear. Reject Chinese (`zho`/`chi`), Korean (`kor`), other languages, missing and bilingual records even from `ndl-boj`. Validate up to 9 cards, next-page deduplication and manual retry. These fixed title queries provide a *sample*, not worldwide English-language coverage, and 504 remains possible during upstream outages.
- NDC genres: sample manga 726.1, fiction NDC 9, business/industry and history; NDC is not the Rakuten genre system.

## Safety/account states
- Check minor, adult and anonymous access.
- Known adult title/description and explicit ONIX codes 01/02/03 should not appear to minors.
- Unknown age classification should be shown, unless an independent adult indicator matches.
- ONIX warning-only 04/05/06/07 alone should not count as verified 18+.
- Check home, search, featured, profile shelves, saved books, review details, crawler direct URLs.
- Confirm privacy and suspended-user filtering. The raw NDL proxy is not currently age-aware: server-side protection remains a distinct review.

## Rights and persistence
- Check NDL source and CC BY 4.0 license credit in client and crawler footer.
- Inspect openBD image rights and records with unavailable/deleted covers.
- Existing user reviews, shelves and favorites survive external provider outages.
- Affiliate purchase buttons exist only for verified ISBN-linked official URLs.

## Failure paths
- NDL and openBD APIs: valid response, bad ISBN, invalid parameters, timeout and 5xx.
- Legacy /api/rakuten returns HTTP 410 with no outbound Rakuten call.
- NDL unavailable: existing reviews remain accessible; no cacheable permanent missing-book error.
- openBD unavailable: NDL book titles still display.
- Staging worker CSP, routing and noindex response headers.

## Regression: NDL gateway timeout and new-arrivals retry
- Verify the NDL proxy can distinguish 504 `ndl_timeout`, upstream overload 503 and generic 502; none should be cached or equated with no results.
- Check a recent (90-day) NDL national query at `idx=1`, then confirm in-process fallback when the national provider fails or its first window has no eligible ISBNs.
- On 502/504, confirm the NDL cursor does **not** increment its offset and that the home section can be retried via **もう一度取得する** without reloading the rest of the home page.
- When NDL returns ISBNs, confirm up to 9 safe covers/cards, correct next-page deduplication, no foreign/Japanese cross-contamination, and no display of unverified fabricated books.
- Record upstream status/response time without logging the user query or access keys; inspect Chrome Network and do not assume a green HTTP-only smoke test covers NDL integration.


### Verify real NDL ISBN representation after this fix
- In staging, confirm `/api/ndl?dpid=iss-ndl-opac-national&idx=1&cnt=27&mediatype=books&from=<recent-date>` returns 200 XML, and inspect the `dc:identifier` / `dcterms:identifier` elements for NDL ISBN values such as `978-4-297-13633-8`.
- Confirm the client converts hyphenated ISBNs to canonical `9784297136338` form and does not discard otherwise valid records (the first 27 RSS results must fill up to 9 safe cards when enough ISBNs exist).
- Repeat with next page and verify ISBN identity, no duplicates, age filtering, and manual retry on intermittent NDL 502/504.
- NDL OpenSearch publication-date `from` and OAI-PMH datestamp `from` have different meanings. A cached OAI-PMH ingestion is a separate change, not a replacement for basic ISBN normalization.



## Commercial-use cover QA (2026-11-02)

- Google Books API `/api/book-covers?isbn=9784488402327` MUST return HTTP 410
  with `provider_disabled_pending_rights` and must NOT contact Google.
- openBD `/api/openbd?isbn=9784488402327` returns JSON and may have an empty
  `summary.cover`. The book still appears with its title and author.
- Books with an **approved** openBD cover use its original HTTPS URL and
  `coverSource == 'openbd'`. Verify the jacket is visible on desktop/mobile.
- Books without approved images show the honest title placeholder
  `表紙画像なし`, with no calls to Open Library.
- Legacy Google/Rakuten/Open Library URLs in saved reviews, posts and
  shelf data MUST NOT trigger network image requests.
- Validate correct source provenance on featured books and the SEO HTML
  book details. No external retail images without appropriate licensing.
- Verify book review posting, NDL search, age safety, and user-owned data are
  unaffected by hiding unapproved images.
- Read `docs/commercial_book_cover_policy_20261102.md` before rollout.
- Only promote to `main` after reviewing all paid feature cover placement
  contexts and any provider withdrawal/delete obligations.

### Publisher-hosted ISBN covers (Akane / Goken)

- Confirm the book with ISBN `9784251096883` displays the unchanged jacket
  from Akane's official site when openBD provides no jacket.
- Confirm ISBN `9784876154647` displays Goken's official low-resolution
  jacket when openBD provides no jacket.
- Check failed/offline image requests show `表紙画像なし` rather than a
  third-party retailer/Google/Open Library image.
- Check untrusted Google/Rakuten URLs saved on old books are **never**
  requested even if an authorized publisher ISBN cover is available.
- Check card and detail views show the entire cover (no `BoxFit.cover`,
  lower text panel overlapping the jacket, or image-overlay badges).
- Verify 404/HTTP errors, CSP and browser loading on desktop/mobile.
- Before production, confirm with publishers whether direct image hotlink
  traffic and any bulk automated access are allowed; this change only
  constructs URLs for visible, checksum-valid ISBNs and does not crawl sites.
- The code needs no new API key, registration, or secret for these publisher
  URLs. Keep Blue Bow (青弓社), Amazon, Google and NDL's retired cover route
  disabled as independent cover fallbacks.


## Staging: language-bearing SRU/DC-NDL (2026-11-02)

A read-only GitHub Actions probe on staging found that OpenSearch returned HTTP
200 and up to 27 items in each of the first `日本`, `Tokyo` and `Japan`
windows, including 19/12/27 ISBN-bearing records respectively. **None of the
81 sampled RSS items contained a language element**. Thus the strict jpn/eng
home filters correctly rejected every item. HTTP 200, Cloudflare HIT and ISBN
counts do **not** prove that an item qualifies for 和書/洋書.

The language-specific home feeds now request the official NDL SRU API
(`recordSchema=dcndl`, `recordPacking=xml`, `onlyBib=true`) through
same-origin `/api/ndl-sru`. The response must carry an explicit
`dcterms:language` value together with a typed ISBN; strict jpn/ja and
eng-only rules remain unchanged. Other book search and new arrivals continue
to use OpenSearch. This does not infer language from provider/title.

Before any production release:
- On staging check `/api/ndl-sru?dpid=iss-ndl-opac-national&title=日本&idx=1&cnt=27` and `/api/ndl-sru?dpid=iss-ndl-opac&title=Tokyo&idx=1&cnt=27` for actual SRU `recordData`, typed ISBN, `dcterms:language`, latency and 502/504 fallback.
- Verify the home 和書 and 洋書 carousels actually render, paginate without ISBN
  duplicates and show only valid single-language records; unknown/mixed
  language records must still be excluded.
- Check missing openBD covers still yield title placeholders, not empty cards.
- Verify the OpenSearch search page, 新着, posts, user shelves and timelines
  continue unchanged.
- SRU may itself be slow or return records with no languages; neither nine
  cards nor first-time requests can be guaranteed until real staging checks
  show eligible records. Do not promote to main on CI success alone.
