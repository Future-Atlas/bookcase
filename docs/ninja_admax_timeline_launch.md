# Ninja AdMax timeline-only integration

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

- Only on `https://www.sharemarium.com/` Flutter Web home timeline.
- Between posts 2–3, 4–5, 6–7 only if another real post follows; maximum 3 placements per page.
- `HtmlElementView` creates a genuine inline `<div class="admax-ads" data-admax-id="...">`. The JS controller queues it, then loads `st/t.js` **asynchronously**.
- The issued banner is **728 × 90 px**. Its dimensions are retained; on narrow screens the banner container permits horizontal scrolling instead of truncating or distorting creatives. For a phone-responsive experience, obtain a dedicated smartphone or PC/SP switching advertisement tag from Ninja AdMax.
- Ad-free members, entitlement lookup failures and other routes must not load the AdMax SDK. Existing SNS / subscription visibility remains unchanged.

## Verification after deployment

1. Confirm the main-branch Flutter CI and production Vercel deployment succeed.
2. With an ad blocker disabled and at least three visible posts, scroll to the first ad slot on a logged-out Chrome browser.
3. Inspect DevTools Network: the **`adm.shinobi.jp/st/t.js`** request should appear. An HTTP 200 for the SDK alone is **not proof** that advertising content has been served.
4. Check the advertisement itself (initial review creative, if provided, or an actual paid creative), desktop and mobile overflow, and Ninja AdMax management dashboard status.
5. Confirm paid ad-free accounts and all non-timeline routes never request the SDK. Check navigation, scrolling and lazy mounts.
6. Update privacy/external-transmission disclosures promptly.

Ninja AdMax's SPA samples do not guarantee delivery. If the request still does not appear, investigate Flutter DOM attachment, browser ad blocker, API entitlement, and consent blockers before attributing it to review delays.
