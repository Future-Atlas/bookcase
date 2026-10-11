# Ninja AdMax timeline-only launch checklist

## Official publisher tag

The publisher-provided code below is copied **verbatim** into an inert
HTML template in web/index.html and is only executed inside a sandboxed
srcdoc iframe when a timeline ad slot is eligible:

<!-- admax -->
<script src="https://adm.shinobi.jp/s/234edc1d1284546b2d177ac7c5531101"></script>
<!-- admax -->

This is a **synchronous** Ninja AdMax tag. It is not safe to dynamically
insert that script into the already-running Flutter SPA; the isolated iframe
allows parser-time execution. Actual rendering and vendor support for this
embedding strategy still require a real-browser check.

## Placement policy

- Flutter Web home timeline on www.sharemarium.com only.
- One slot between posts 2-3, 4-5 and 6-7, only when the next post exists.
- Maximum **three ad slots per page**, following Ninja AdMax guidance.
- For the trial, NINJA_ADMAX_POSTS_PER_AD defaults to 2. Use the build
  argument --dart-define=NINJA_ADMAX_POSTS_PER_AD=5 for normal operation.
- NINJA_ADMAX_ENABLED remains false unless explicitly enabled using
  --dart-define=NINJA_ADMAX_ENABLED=true in the approved Web build.
- No native app advertisements and no ads on other routes, guest login,
  settings, profiles, category screens or SEO-rendered HTML.
- For authenticated users, paid ad-free entitlements are honored and
  failures of entitlement checks suppress advertising requests.
- Existing SNS features, subscription UI flags and Terms remain unchanged.

## Preconditions for production activation

1. Verify the supplied tag is for a general-audience, inline placement,
   with the production URL registered in Ninja AdMax. Disable overlays,
   popups and unwanted adult creatives in the provider settings.
2. Confirm this synchronous tag works inside srcdoc iframes. If it does
   not, obtain an official asynchronous tag rather than injecting the
   synchronous tag directly into Flutter's dynamic document.
3. Update Privacy Policy and external-transmission disclosures to cover
   actual Ninja AdMax data collection, recipients, cookies and opt-out.
   Obtain any required consent before loading the vendor code.
4. Check PC/smartphone, post counts 0-2 and 3+, disabled/ad-free user,
   entitlement failure, route changes, scrolling, SPA navigation, and
   browser back/forward. Check that no more than 3 frames are requested.
5. Enable the Web flag only after those checks pass, monitor the real
   network requests and Ninja AdMax review/approval and revert if needed.

Passing CI does not establish live ad delivery or vendor approval.
