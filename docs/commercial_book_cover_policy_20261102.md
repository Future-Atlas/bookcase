# Book cover licensing policy for commercial Sharemarium (2026-11-02)

## Decision: Only book covers returned by openBD are enabled

Sharemarium is intended to be monetized. Source availability is **not**
permission for commercial use. Google Books, Open Library and Rakuten
retailer image URLs must not be used as generic automatic cover fallback.

**Permitted for book introduction/promotion under published provider terms:**

- **openBD**: explicitly permits book introduction/promotion by individuals,
  organizations and companies. This is **not** blanket permission to modify,
  resell, sublicense or retain withdrawn book images. The app must keep book
  descriptions and cover data tied to books and respond to corrections/removal.
  Source: https://openbd.jp/terms/
- Publisher/author-supplied images: may be added in a *separate* feature only
  after recording explicit grants **by title or publisher** (allowed usage,
  monetization, display context, expiry, withdrawal and attribution).
  Source context: https://www.hanmoto.com/permission-for-use/agreement

**Not enabled:**

- Google Books: the Google Books API terms limit charging fees for use of an
  application without a separate agreement or written permission. Dynamic
  Links' terms/context for the paid product are not cleared. The proxy remains
  present but returns HTTP **410** without calling Google.
  https://developers.google.com/books/terms
- Open Library: public-cover embedding is documented but a cover URL alone
  does not convey commercial rights for the underlying copyrighted artwork;
  no automatic fallback until an appropriate license is documented.
  https://openlibrary.org/dev/docs/api/covers
- Rakuten Web Service: its published FAQ prohibits earning revenue *other
  than affiliate proceeds* through the API. Do not silently reuse retail
  product images as a generic cover provider for a paid reading app.
  https://webservice.faq.rakuten.net/hc/ja/articles/900001970826
- NDL search's book-cover endpoint was discontinued on 2026-03-31; it is not
  a replacement. https://ndlsearch.ndl.go.jp/news/20260401_thumbnail

## Implementation

1. `OpenBdApi.enrich` uses NDL book identity and ISBN-exact openBD metadata,
   returns records without querying Google.
2. `BookCoverImage` only renders HTTPS cover URLs from **fresh openBD
   metadata** (`coverSource == 'openbd'`) or the official openBD cover CDN for
   older, unlabelled saved-book data. It blocks known Google/OL/Rakuten
   hosts even if a legacy record claims openBD as its source.
3. Images from old posts, profiles and saved items without evidence of a
   cleared source show `表紙画像なし`. Never fetch another provider based
   solely on an ISBN.
4. The old `/api/book-covers` route returns HTTP 410 with no outbound calls;
   the same behavior applies to Vercel and Cloudflare routing.
5. NDL book results, adult-content policy, user reviews, user profiles, book
   search and stored user content are **not** deleted.

## Limitations and obligations

- openBD limits usage to book introduction and promotion, prohibits
  unapproved changes, and asks consumers to apply updates and withdrawals.
  The product owner should confirm that **every** planned paid-feature cover
  placement fits that scope before rolling out commercially.
- Source material may be deleted or changed. Do not permanently retain a
  URL as authoritative without refreshing provider metadata. Respect removal
  requests and keep a way to suppress withdrawn covers.
- Google Books image coverage may fall considerably: in the NDL recent-book
  sample of 100 ISBNs, openBD had 2 usable URLs, Google returned another
  54, and 10 Google requests remained unverified due to HTTP 503.
  See: https://github.com/Future-Atlas/bookcase/actions/runs/41363733297
  That convenience does not grant a commercial license.
- Browser rendering is NOT verified by HTTP CI alone. Check desktop/mobile
  views, post cards, profile, reviews, image provider URLs and error console
  in staging. Only then consider a separate production release.
- For broader commercial coverage, obtain a direct license from JPO/JPRO
  or participating publishers; create a rights registry and a provider
  implementation **only after** the applicable permissions are documented.
  Do not scrape commercial shops, proxy image files, or republish assets
  until rights have been cleared.
