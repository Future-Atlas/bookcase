abstract final class FeatureFlags {
  // Subscription UI stays hidden until the Terms of Service and related
  // billing disclosures are ready for publication. Keep the backend and
  // tests in place so the feature can be re-enabled with a single flag.
  static const bool subscriptionUiEnabled = false;

  // Favorites are available on the free plan with the existing three-book
  // limit. Paid-plan UI remains disabled independently.
  static const bool favoritesUiEnabled = true;

  // Want-to-read also launches alongside subscriptions. Preserve existing
  // records while the user-facing entry points remain hidden.
  static const bool wantToReadUiEnabled = subscriptionUiEnabled;
}
