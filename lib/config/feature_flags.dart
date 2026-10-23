abstract final class FeatureFlags {
  // Subscription UI stays hidden until the Terms of Service and related
  // billing disclosures are ready for publication. Keep the backend and
  // tests in place so the feature can be re-enabled with a single flag.
  static const bool subscriptionUiEnabled = false;

  // Favorites are part of the future subscription release. Preserve stored
  // data and backend support, but keep every user-facing entry point hidden
  // until the subscription UI is approved and enabled.
  static const bool favoritesUiEnabled = subscriptionUiEnabled;
}
