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
