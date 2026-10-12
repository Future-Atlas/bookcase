# Flutter 3.47.7 / Dart 3.13 migration (Issue #76)

## Scope

- Pin Flutter 3.47.7 consistently in `.fvmrc`, standard CI, Android build validation, the Vercel staging/production Web workflows, and the Supabase production workflow's Flutter validation step.
- Raise `pubspec.yaml` Dart SDK constraint from `^3.12.0` to `^3.13.0`.
- Upgrade `xml` to `7.1.0` (and `petitparser` to `7.1.0`) and `google_fonts` to `9.0.0`. The latter adds transitive `material_ui`, `cupertino_ui`, `intl` and `flutter_localizations`.
- Retain the separately reviewed patch-level Dependabot updates for `url_launcher`, `shared_preferences` and `image_picker`.
- Enforce a reproducible checked-in `pubspec.lock` by checking for differences after `flutter pub get` in the CI job.

## Test gates

- Required CI job: Flutter analyze, all Flutter tests, Web release build, Vercel API tests, Edge Functions type checks.
- Dedicated Android job: `flutter build apk --debug` on pull requests affecting the Android workflow.
- Staging Vercel deployment should be verified after the upgrade lands on `develop`; production should not be promoted without confirming layout/fonts, authentication, ads, privacy, and billing flows.
- After production rollout, check mobile/desktop text and icon rendering and ensure the Ninja AdMax publisher-issued banner remains unchanged.

## Release precautions

- Flutter 3.47.7 supersedes the previous Flutter 3.44.9 runtime (Dart 3.12.x).
- This is a **toolchain migration**, not only a package bump. A green CI job is necessary, but on-device visual regression checks are still required.
- Supabase production migration deployment has a separate `SUPABASE_ACCESS_TOKEN` authentication issue (#82). SDK migration does not repair that secret. Do not skip authentication or rewrite migration history to force a deployment.
- Do not merge the SDK change to production `main` while any required CI check or platform validation is failing.
