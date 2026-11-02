# Book cover licensing policy for commercial Sharemarium (2026-11-02)

## Decision: openBD first, then ISBN-exact covers from two explicitly permission-granting publishers

Sharemarium is intended to be monetized. Source availability is **not**
permission for commercial use. Google Books, Open Library and Rakuten
retailer image URLs must not be used as generic automatic cover fallback.

**Permitted for book introduction/promotion under published provider terms:**

- **openBD**: explicitly permits book introduction/promotion by individuals,
  organizations and companies. This is **not** blanket permission to modify,
  resell, sublicense or retain withdrawn book images. The app must keep book
  descriptions and cover data tied to books and respond to corrections/removal.
  Source: https://openbd.jp/terms/
- **あかね書房 / Akane Shobo**: directly permits individual and company book
  introductions on websites using unmodified cover images copied from its
  own site, without prior request. An ISBN-exact official-site image URL
  template for the publisher's assigned 978-4-251 ISBNs is enabled only as
  fallback when an approved openBD jacket is absent.
  https://www.akaneshobo.co.jp/mail/form_copyright/coveronly.php
- **語研 / Goken**: explicitly permits book covers for introductions, reviews
  and affiliate-based promotion without prior permission. Its ISBN-exact
  official-site low-resolution image URL template for 978-4-87615 ISBNs is
  enabled only as fallback when openBD has no approved jacket.
  https://www.goken-net.co.jp/info/company_profile.html
- **Other publisher/author-supplied images**: disabled unless source-specific
  approval, publication credit and image access conditions are recorded.
  Publisher-wide licenses must not be inferred from a book's mere availability
  on a publisher site. Source context:
  https://www.hanmoto.com/permission-for-use/agreement

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
2. `BookCoverImage` prefers HTTPS cover URLs with trustworthy openBD
   provenance (`coverSource == 'openbd'`) or the official openBD cover CDN
   for older, unlabelled saved-book data.
3. If no approved openBD image exists, `OfficialPublisherCovers` uses an
   **ISBN-13 checksum** and an **explicit publisher-assigned prefix
   allowlist** to construct an official Akane or Goken cover URL. No arbitrary
   publisher lookup, HTML scraping, bulk site crawl or external API key
   is performed. Only one image request is made when that book is rendered.
   A missing or failed image shows `表紙画像なし`.
4. All jackets are rendered with `BoxFit.contain`; book-card labels occupy a
   separate area and do not obscure the cover. Old Google/Rakuten/Open Library
   images remain blocked, even if the stored post contains their URLs.
5. The old `/api/book-covers` route returns HTTP 410 with no outbound calls;
   the same behavior applies to Vercel and Cloudflare routing.
6. NDL book results, adult-content policy, user reviews, user profiles, book
   search and stored user content are **not** deleted.

## Limitations and obligations

- openBD limits usage to book introduction and promotion, prohibits
  unapproved changes, and asks consumers to apply updates and withdrawals.
  The product owner should confirm that **every** planned paid-feature cover
  placement fits that scope before rolling out commercially.
- Akane and Goken permit use of their **own** published jackets to introduce
  books on the web, including individual/company or affiliate contexts. The
  user plans ad revenue and an optional *ad removal only* paid membership,
  not sale of image files. Nonetheless, their published pages do **not**
  expressly address automated ISBN-path generation, hotlink bandwidth, or
  unlimited high-traffic downloads. Before high-volume/production use,
  request written clarification if publisher hosting or monetization terms
  are uncertain. The published permission is not a blanket crawling license.
- Both official image URL layouts are inferred from multiple live book pages;
  their continued availability and suitability for remote embedding must be
  checked in a staging browser before production. Images may fail to load,
  be replaced, or be removed by the publisher; no rights-free fallback is used.
- 青弓社 is not an automatic source yet. Its conditions require author/title/
  publisher together beside the jacket plus notice of the publication URL.
  Its cover overlap with openBD is significant. Maintain this exclusion until
  those obligations are demonstrably met throughout the UI.
  https://www.seikyusha.co.jp/shoeinogoriyou/
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
