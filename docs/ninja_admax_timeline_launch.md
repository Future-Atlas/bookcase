# Ninja AdMax: asynchronous native timeline integration

## Why this change was needed

The exact original **synchronous** Ninja AdMax tag was:

<!-- admax -->
<script src="https://adm.shinobi.jp/s/234edc1d1284546b2d177ac7c5531101"></script>
<!-- admax -->

The text is retained unchanged in an inert HTML template in
`web/index.html`, but it is no longer used for ad delivery. Loading
it in a `srcdoc` iframe produced no visible Ninja AdMax network request.
Do not dynamically execute this /s/ tag on the Flutter SPA page: it uses
`document.write` and can damage the running document.

Ninja AdMax describes its SPA implementation here:
https://www.ninja.co.jp/admax/help/faq/13947/
https://github.com/ninjatools/admax-spa-examples

**A separate publisher-issued asynchronous tag must be obtained.**
Its `admax_id` must not be guessed from the /s/ URL.

## Configuration

Set GitHub Actions **Variables** for the production workflow:

- `NINJA_ADMAX_ASYNC_ID`: the asynchronous `admax_id` issued by Ninja AdMax
- `NINJA_ADMAX_ASYNC_TYPE`: `switch` for a PC/SP switching tag or
  `banner` for a vendor-issued banner tag. Default: `switch`.

The production build already sets `NINJA_ADMAX_ENABLED=true` and
`NINJA_ADMAX_POSTS_PER_AD=2`, and now accepts those two variables.
Without a valid asynchronous ID, the timeline intentionally shows
**no empty ad placeholders and makes no third-party advertising requests**.
This prevents mistaking the literal 「広告」 label for a real advertisement.

After updating the variables, **rerun the production Web deployment**
so the values are included in Flutter's compiled JavaScript.

## Rendering

- Flutter Web creates the real DOM node directly using `HtmlElementView`:
  `<div class="admax-switch" data-admax-id="...">` for `switch`;
  `<div class="admax-ads" data-admax-id="...">` for `banner`.
- The page queues `{admax_id, type}` and loads
  `https://adm.shinobi.jp/st/t.js` asynchronously; no wrapper iframe.
- The SDK itself may produce its own creative iframes as normal.
- The loader starts only on the production homepage, after a slot
  exists and the visitor is eligible. Paid ad-free accounts, error
  responses and other routes never initiate a new SDK load.
- The maximum remains 3 inline positions, between posts 2-3, 4-5,
  and 6-7 where the next post exists. Use 5 instead of 2 for normal operation.
- SDK lifecycle checks use a DOM observer in addition to Flutter events
  because platform-view creation can precede DOM attachment.

## Real verification still required

1. Obtain and verify the exact *asynchronous* tag and type from the
   provider's management UI. Do not substitute the old synchronous hash.
2. Set the GitHub Actions variables and redeploy.
3. Open the homepage with >=3 real posts and inspect Network:
   `adm.shinobi.jp/st/t.js` should be requested only when an eligible
   slot mounts. A successful SDK request alone does not prove ads render.
4. Verify actual vendor creatives/initial review placeholder, PC/mobile,
   ad blockers disabled, paid ad-free accounts and other routes.
5. Confirm the Ninja AdMax review status and update the relevant
   privacy/external-transmission disclosures.

Officially, SPA integrations are not guaranteed by Ninja AdMax.
