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
- **Placement 2:** inside the home screen's embedded timeline, after post 2 and before post 3, if those posts exist.
- **Three advertisements maximum per page**, shared by the two genre separators and the timeline. This follows [the publisher's three-placement recommendation](https://www.ninja.co.jp/admax/help/faq/4269/). Consequently the embedded timeline no longer uses placements after posts 4 and 6 while two category placements are reserved. If one or both genre separators have no content, the unused positions are not reused by the timeline.
- `NINJA_ADMAX_POSTS_PER_AD=2` is used during the trial; the normal setting of `5` moves **the single timeline placement** to after post 5. Category placements are independent of the post interval.
- Each ad uses one of the fixed **unique numeric slot indices 0, 1, 2** to avoid collisions in the SPA ad controller and to share the same publisher SDK.
- `HtmlElementView` creates a genuine inline `<div class="admax-ads" data-admax-id="...">`. The JS controller queues it, then loads `st/t.js` **asynchronously**.
- The issued banner is **728 × 90 px**. Its dimensions are retained; on narrow screens the banner container permits horizontal scrolling instead of truncating or distorting creatives. For a phone-responsive experience, obtain a dedicated smartphone or PC/SP switching advertisement tag from Ninja AdMax.
- Ad-free members, entitlement lookup failures and other routes must not load the AdMax SDK. Existing SNS / subscription visibility remains unchanged.

## Verification after deployment

1. Confirm the main-branch Flutter CI and production Vercel deployment succeed.
2. With an ad blocker disabled, open the real homepage in a logged-out Chrome browser. Confirm genre separators appear only when both adjacent book rows contain books, and that the third slot appears after the first two timeline posts (when at least 3 posts are available).
3. Inspect DevTools Network: the **`adm.shinobi.jp/st/t.js`** request should appear. An HTTP 200 for the SDK alone is **not proof** that advertising content has been served.
4. Check the advertisement itself (initial review creative, if provided, or an actual paid creative), desktop and mobile overflow, and Ninja AdMax management dashboard status.
5. Confirm paid ad-free accounts and non-home routes never request the SDK; confirm search and single-genre views have no ad slots. Check the maximum of three requests/placements, category pagination, navigation, scrolling, and lazy mounts.
6. Update privacy/external-transmission disclosures promptly.

Ninja AdMax's SPA samples do not guarantee delivery. If the request still does not appear, investigate Flutter DOM attachment, browser ad blocker, API entitlement, and consent blockers before attributing it to review delays.
