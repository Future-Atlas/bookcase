# Ninja AdMax timeline-only launch checklist

This change replaces automatic AdSense loading with one **optional** Ninja
AdMax placement. It does **not** activate ads until the exact publisher
credentials and compliant legal disclosures are ready.

## Implementation

- Flutter Web home timeline only, after the third real post (requires >=3 posts).
- Never on login, settings, book catalog, genre-only, empty timeline,
  profile, or crawler-rendered SEO HTML.
- Clearly labeled 「広告」, separated from post buttons and reactions.
- Never an overlay/popup/floating banner. **Disable overlay settings in Ninja
  AdMax dashboard**, since the publisher can override the inline placement.
- One request maximum per browser page load; vendor script cannot reliably be
  removed on client-side navigation. Navigation away from the allowed page
  forces a reload after ads have loaded.
- Ad-free paid subscriptions are checked through /api/ad-entitlement. Checks
  fail closed for authenticated users on API failures.
- Config is disabled by default. Android/iOS never load Web publisher tags.

## Operator steps before enabling

1. Register the **exact** production URL:
   https://www.sharemarium.com/
2. Select an **asynchronous PC/SP switch tag**, not the legacy synchronous
   `https://adm.shinobi.jp/s/...` script. The slot implementation expects
   `admax-switch`, `admax_id`, `type: "switch"` and
   `https://adm.shinobi.jp/st/t.js`. The ID must belong to that format.
3. Use general-audience settings appropriate for a book review SNS.
   Disable adult creatives and **all overlays**.
4. Confirm the actual vendor-issued tag matches the shape above. If it
   differs, adapt the integration before enabling; do not force the ID into
   the wrong tag type.
5. Confirm privacy-policy and external-transmission notices accurately cover
   Ninja AdMax's actual recipient, data categories, purposes, third-party
   recipients, cookies and opt-out procedure. Obtain any required consents
   before activating. Current old AdSense disclosures are **not sufficient**.
   Do not change the operative Terms of Service solely to enable advertising.
6. Provide Flutter Web build-time values (not secrets):
   `--dart-define=NINJA_ADMAX_ENABLED=true`
   `--dart-define=NINJA_ADMAX_SWITCH_ID=<issued switch admax_id>`
   in the web production build pipeline. Deploying with no values leaves the
   ad slot fully disabled. Also ensure the flag remains disabled in preview,
   staging and any local environments.
7. Verify as a guest and a standard authenticated user: exactly one label
   and publisher ad request between posts 3 and 4 on the timeline. Check PC
   and mobile breakpoints; Ninja may require distinct sizes/settings.
8. Verify ad-free account, login/settings/profile/genre/empty timelines,
   route changes, responsive layout and browser extensions.
9. Confirm tag is recognized by Ninja AdMax. Their automated check begins
   after a real tag is detected. Do not self-click or encourage clicks.
10. Keep the feature off if any validation fails.

## Known limitations

The review outcome is controlled by Ninja AdMax, not this repository.
Since no actual advertiser-issued tag is available, no real ad impression,
approval, or mobile rendering has been verified. The service should stay
disabled until all operator checks and legal disclosure updates are finished.
