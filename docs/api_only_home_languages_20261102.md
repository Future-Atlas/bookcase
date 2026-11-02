# API-only home language feeds (staging validation)

## Why this change is needed

NDL OpenSearch on staging returned HTTP 200 and ISBN-bearing records but **no
language elements in any of 81 sampled RSS items**. Existing exact `jpn` /
`eng` home feed checks correctly rejected all records. Caching the same RSS
cannot fix missing metadata, and NDL SRU / OAI-PMH individual detail lookups
returned 429 or timed out in live trials.

## Minimal-cost approach

- **No new Supabase table, SQL migration or saved bibliographic records.**
  Existing Supabase auth/user posts/shelves remain unchanged.
- Only homepage 和書 and English-only 洋書 use read-only `/api/home-catalog`.
  新着 and ordinary search stay on NDL, popular remains Sharemarium posts.
- The Cloudflare Worker checks a strict allowlist of `lang`, `topic` and
  `page` and calls Open Library Search API once to get up to 60 edition keys.
  It then calls the **batched** Books API once for those same editions.
- Books are accepted only when the **specific edition** explicitly has one
  language (jpn/eng) and a valid checksum-verified ISBN-13, or a valid ISBN-10
  convertible to an ISBN-13. Never take an ISBN from a multilingual *work*.
- No Google Books, retailer, or Open Library cover images. Existing
  openBD/publisher-approved covers and title-only placeholders remain.
- API returns are cached at the Cloudflare edge for at most 10 minutes.
  Identical in-flight requests are coalesced per Worker isolate. 429/5xx,
  timeouts and malformed responses never become persistent empty-catalog data.
- Initial-load language feeds are sequential with each other, to protect the
  low-volume provider limit, but are **parallel to new-arrivals** so a slow
  NDL call cannot block all home content.
- Adult-content safety and user reviews still pass through the existing
  BookRepository and Supabase policies.

## Real read-only sample checks (2026-11-02)

1. Open Library Search API, limited to 20 Japanese and 20 English matched
   editions: HTTP 200 in about 1.4s and 2.5s. All selected edition language
   tags were explicitly jpn/eng.
2. A batched /api/books.json lookup found valid language metadata and
   ISBN-10 in 20 of 20 Japanese and 19 of 20 English sample editions.
   Filtering by ISBN in the query reduced the number of unsuitable records.
   No assumption that all future queries will return nine books.

## Limits and required acceptance checks

Open Library describes its APIs as low-volume tools for human-directed
discovery, **not a backend for high-traffic commercial applications**.
Its default unidentified limit is 1 request/second. Respect caching,
rate limits, provider terms, and HTTP Retry-After. Identify this application;
contact the provider before scaling traffic and obtain any needed commercial
permissions. Official guidance: https://openlibrary.org/developers/api
We do not use its cover API.

On staging, check:

- `/api/home-catalog?lang=jpn&topic=%E6%97%A5%E6%9C%AC&page=1`
- `/api/home-catalog?lang=eng&topic=Japan&page=1`
- For both, verify HTTP 200 JSON with `books`, strict `languageCode`,
  13-digit checksum-valid `isbn`, and a warm `cf-cache-status: HIT`.
- Confirm at least one real title card appears in both 和書 and 洋書, with
  pagination, no cross-language books, adult-content filtering, and fallback
  title placeholders when no approved cover exists.
- Confirm 新着, existing NDL search, user shelves, reviews, timeline, and
  SEO continue working. New arrivals may still have NDL cold-query latency.
- Simulate 429/5xx and malformed metadata: no cache and manual retry.
- Do **not** promote to `main` without a separate review of coverage,
  performance, and third-party service terms. The home feeds are examples,
  not comprehensive or necessarily today's latest books.

Future growth: monitor anonymous home API hit counts and external rate
limits. Before traffic grows, arrange permitted higher-capacity metadata
access or introduce a tightly scoped, licensed catalog if economical.
