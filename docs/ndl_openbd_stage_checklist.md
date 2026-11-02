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
- 洋書: confirm `ndl-boj` candidates, holdings fallback, 27-item refill, 9 cards when possible, next-page deduplication and explicit non-Japanese language codes (`eng`, `spa`, etc.) or verified `ndl-boj` provider provenance for unknown tags. Never display Japanese-only holdings or unclassified missing-language holdings merely because `English` appears in the title. Complete worldwide foreign-book coverage remains a known limitation.
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
