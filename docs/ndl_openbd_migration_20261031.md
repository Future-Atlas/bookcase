# NDL + openBD migration (PR #194, draft)

## Intent and boundaries

Replace Rakuten Web Service catalog calls with National Diet Library Search as the primary source and openBD as optional enrichment. Keep all user-authored posts, shelves, favorites, reactions and ISBN-based links intact. The legacy `/api/rakuten` responds with 410 and no longer contacts Rakuten.

### Functional mapping

- Home/new arrivals: existing `新着` section uses NDL's `iss-ndl-opac-inprocess` provider, 27 candidate records, publication-date sorting of the returned page, first nine displayed. This is not equivalent to Rakuten's global `-releaseDate` sort: NDL arrival/creation and publication date differ; real freshness must be measured.
- Home foreign books: existing `English` section uses NDL keyword search; this is not a reliable language filter. Verify coverage before release.
- Home popular: existing `ベストセラー` section now fetches NDL records. Rakuten reviews are gone, so the catalog is **not** a true bestseller list. Replace the backing ranking with actual internal post/bookmark activity or rename the presentation after product review.
- Keyword search: original title, author and publisher field priority, exact-match handling and the 10/5/5 quota per 20 results remain in `BookRepository.rankSearchResults`. NDL has different field semantics and search inventory, so exact result equivalence is not possible.
- Cover and descriptions: `OpenBdApi.enrich` fetches at most 25 ISBNs per request. Missing or failed enrichment must not remove books.
- Safety: `ContentSafetyService` keeps existing term matching and optional Rakuten genre history, now also reads `adultContentFlag` derived from explicit ONIX audience warnings found in openBD data. Unknown is not safe/verified. Public SEO filters known adult terms and requests non-age-restricted review records.
- Purchase links: Rakuten affiliate **API** is retired; manually verified links may be attached to ISBNs in `lib/config/rakuten_affiliate_links.dart`. A missing verified product link hides the purchase button; no ISBN-to-Rakuten-product link is invented.

### Unresolved prerequisites before release

1. **NDL rights/application**: NDL states that revenue-bearing sites (including advertising) are commercial use; verify that the exact national/new-arrival provider records are covered by advance authorization and implement the requested attribution. For continual API usage, notify the NDL about the service and expected traffic. See https://ndlsearch.ndl.go.jp/help/api and https://www.ndl.go.jp/data/data_service/jnb .
2. **openBD rights and safety data**: Confirm whether the actual current production records contain usable ONIX ratings and what cover image redistribution/hotlink restrictions apply. Check 100-300 ISBNs including manga, Japanese novels, business books, foreign titles and known restricted publications. Do not assume 'no adult flag' means minors are safe.
3. **Affiliate compliance**: Confirm Sharemarium's website/user-generated-content placement with Rakuten Affiliate separately. Collect official product-level affiliate URLs; no automatic complete ISBN mapping is possible without a legitimate permitted source.
4. **Publishing order**: Update credits and content policies, sample staging search genres and age groups, SEO direct paths, ad scripts, cached featured book data and legacy provenance migration. Do not deploy automatically.
5. **Historical data**: Run the existing provenance inventory. Do not delete old metadata or user posts until source licensing and retention decisions are reviewed.
6. **Search quality**: Compare NDL with existing production behavior: title/author/publisher exact match, pagination (idx), NDC mapping, Japanese manga, foreign language, no-ISBN rows, duplicate ISBNs, and incomplete new-arrival provider results.
7. **Infrastructure**: Since this branch no longer uses the Rakuten DO coordinator, remove old Durable Object bindings in a *separately reviewed* infrastructure cleanup only after migration validation.

## Rollback and verification

PR stays draft, without merge/deployment. Existing `develop` is unaffected. CI checks validate syntax and unit assumptions but do not substitute for permitted real-service traffic or staging. No production keys are required for the NDL/openBD public endpoints; Supabase staging credentials are required for integration QA.
