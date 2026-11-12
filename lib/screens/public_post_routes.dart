import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/profile_page_color.dart';
import '../services/supabase_service.dart';
import '../widgets/primary_bottom_navigation.dart';

import 'account_suspension_gate.dart';
import 'legal_consent_screen.dart';
import 'post_detail_screen.dart';
import 'profile_onboarding_screen.dart';
import 'book_list_screen.dart';

/// Keep human-facing post URLs in Flutter; Vercel serves their SSR equivalents
/// only to crawlers. These routes must not fall back to the home screen.
Route<void>? publicPostRoute(RouteSettings settings) {
  final uri = Uri.tryParse(settings.name ?? '');
  if (uri == null) return null;
  final segments = uri.pathSegments;
  if (segments.length == 2 &&
      segments.first == 'book' &&
      RegExp(r'^(\d{13}|\d{9}[\dXx])$').hasMatch(segments[1])) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => AccountSuspensionGate(
        child: LegalConsentGate(
          child: ProfileOnboardingGate(
            child: Scaffold(
              appBar: AppBar(title: const Text('書籍情報')),
              body: BookListScreen(initialBookId: segments[1]),
            ),
          ),
        ),
      ),
    );
  }
  if (segments.isEmpty || segments.first != 'posts') return null;
  final Widget screen;
  if (segments.length == 1) {
    screen = const PublicPostsScreen();
  } else if (segments.length == 2 &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(segments[1])) {
    screen = PostDetailScreen(postId: segments[1]);
  } else {
    return null;
  }
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AccountSuspensionGate(
      child: LegalConsentGate(child: ProfileOnboardingGate(child: screen)),
    ),
  );
}

class PublicPostsScreen extends StatelessWidget {
  const PublicPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accentColor = ProfilePageColors.colorFor(
      context.watch<SupabaseService?>()?.activePageColorKey,
    );
    return Scaffold(
      bottomNavigationBar: PrimaryBottomNavigation(
        accentColor: accentColor,
        selectedIndex: 0,
        onTimeline: () {},
        onHome: () => Navigator.of(context)
            .pushNamedAndRemoveUntil('/', (route) => false),
        onMyPage: () => Navigator.of(context)
            .pushNamedAndRemoveUntil('/mypage', (route) => false),
      ),
      appBar: AppBar(
        title: const Text('タイムライン'),
      ),
      body: const BookListScreen(timelineOnly: true),
    );
  }
}
