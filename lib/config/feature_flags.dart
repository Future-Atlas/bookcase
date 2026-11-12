abstract final class FeatureFlags {
  // Subscription UI stays hidden until the Terms of Service and related
  // billing disclosures are ready for publication. Keep the backend and
  // tests in place so the feature can be re-enabled with a single flag.
  static const bool subscriptionUiEnabled = false;

  // Keep existing favorite records, but do not display favorite entry points.
  static const bool favoritesUiEnabled = false;

  // Want-to-read is a standard, free reading-list feature.
  static const bool wantToReadUiEnabled = true;
}
