abstract final class FeatureFlags {
  // Subscription UI stays hidden until the Terms of Service and related
  // billing disclosures are ready for publication. Keep the backend and
  // tests in place so the feature can be re-enabled with a single flag.
  static const bool subscriptionUiEnabled = false;

  // The want-to-read entry points launch alongside subscriptions; favorites stay public.
  static const bool wantToReadUiEnabled = subscriptionUiEnabled;
}
