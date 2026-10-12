# Ninja AdMax home-only genre and timeline integration

## Exact publisher-issued asynchronous tag

The publisher provided the following asynchronous banner tag (preserved **verbatim** in an inert template in `web/index.html`):

```html
<!-- admax -->
<div class="admax-ads" data-admax-id="234edc1d1284546b2d177ac7c5531101" style="display:inline-block;width:728px;height:90px;"></div>
<script type="text/javascript">(admaxads = window.admaxads || []).push({admax_id: "234edc1d1284546b2d177ac7c5531101",type: "banner"});</script>
<script type="text/javascript" charset="utf-8" src="https://adm.shinobi.jp/st/t.js" async></script>
<!-- admax -->
```

The active Flutter SPA integration uses the same authorized `admax_id`, `type: "banner"`, `.admax-ads` element and `https://adm.shinobi.jp/st/t.js` SDK. The inert reference template does **not execute** again; loading its scripts directly would duplicate advertisements.

The original synchronous `/s/234edc1d1284546b2d177ac7c5531101` tag is kept unchanged in another inert template for reference only, **not executed**. No app-created `srcdoc` iframe is used.

## Production build configuration

The GitHub Actions `.github/workflows/deploy.yaml` build uses the publisher-provided public values:

- `NINJA_ADMAX_ENABLED=true`
- `NINJA_ADMAX_POSTS_PER_AD=2` (temporary trial; normal use `5`)
- `NINJA_ADMAX_ASYNC_ID=234edc1d1284546b2d177ac7c5531101`
- `NINJA_ADMAX_ASYNC_TYPE=banner`

No GitHub Actions secret or additional variable is needed for the published advertisement ID. Staging and native apps remain OFF. A missing or invalid ID prevents empty 「広告」 placeholders and vendor requests.

## Placement and appearance

- **Only on `https://www.sharemarium.com/` Flutter Web home screen.** Individual genre routes, search results, profiles, and settings never receive additional ad slots.
- **Placement 0:** after the 「おすすめの本」 carousel and before the 「洋書」 carousel. Only when both sections actually contain books.
- **Placement 1:** after the 「洋書」 carousel and before 「人気作品」. Only when both sections actually contain books.
- **Placement 2 onward:** inside the home screen's embedded timeline, after every 2nd, 4th, 6th, 8th, etc. real post, **only if a next real post exists**. The slot indices are 2, 3, 4, 5, ... to remain unique across the page.
- **No application-imposed maximum ad count per page.** The actual number of timeline slots is derived from the available post count and `NINJA_ADMAX_POSTS_PER_AD`. Both book-genre separators remain independent of the timeline. An empty adjacent genre means its separator ad is not rendered.
- The [Ninja AdMax official FAQ](https://www.ninja.co.jp/admax/help/faq/4269/) **still recommends up to three ads on one page**, and warns that larger counts may not display correctly. Removing Sharemarium's guard does **not** change the ad provider's serving limits, ad quality, eCPM, or publisher terms. More app-rendered slots do not guarantee more paid impressions. Verify actual banners and earnings separately.
- `NINJA_ADMAX_POSTS_PER_AD=2` is used during the trial; switching it to `5` places ads after posts 5, 10, 15, ... when more posts exist, without a maximum. Book-genre placements are independent of this setting.
- The genre separators keep unique indices 0 and 1. The embedded timeline uses monotonically increasing indices starting at 2. The Flutter widget and SPA controller no longer reject slots based on a hardcoded maximum.
- `HtmlElementView` creates a genuine inline `<div class="admax-ads" data-admax-id="...">`. The JS controller queues it, then loads `st/t.js` **asynchronously**.
- The issued banner is **728 × 90 px**. Its dimensions are retained; on narrow screens the banner container permits horizontal scrolling instead of truncating or distorting creatives. For a phone-responsive experience, obtain a dedicated smartphone or PC/SP switching advertisement tag from Ninja AdMax.
- Ad-free members, entitlement lookup failures and other routes must not load the AdMax SDK. Existing SNS / subscription visibility remains unchanged.

## Verification after deployment

1. Confirm the main-branch Flutter CI and production Vercel deployment succeed.
2. With an ad blocker disabled, open the real homepage in a logged-out Chrome browser. Confirm the two genre separators appear only when both adjacent book rows contain books, and that additional timeline slots appear after posts 2, 4, 6, and 8 (provided another real post follows).
3. Inspect DevTools Network: the **`adm.shinobi.jp/st/t.js`** request should appear. An HTTP 200 for the SDK alone is **not proof** that advertising content has been served.
4. Check the advertisement itself (initial review creative, if provided, or an actual paid creative), desktop and mobile overflow, and Ninja AdMax management dashboard status.
5. Confirm paid ad-free accounts and non-home routes never request the SDK; search and single-genre views must not display ads. Test more than three simultaneous and lazily mounted slots, genre pagination, navigation, scrolling, and no duplicate SDK injections for a batch.
6. Update privacy/external-transmission disclosures promptly.

Ninja AdMax's SPA samples do not guarantee delivery. If the request still does not appear, investigate Flutter DOM attachment, browser ad blocker, API entitlement, and consent blockers before attributing it to review delays.
