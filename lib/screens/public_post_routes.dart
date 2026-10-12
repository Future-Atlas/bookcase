import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../services/supabase_service.dart';
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

class PublicPostsScreen extends StatefulWidget {
  const PublicPostsScreen({super.key});

  @override
  State<PublicPostsScreen> createState() => _PublicPostsScreenState();
}

class _PublicPostsScreenState extends State<PublicPostsScreen> {
  late Future<List<Post>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = _load();
  }

  Future<List<Post>> _load() async {
    // Retain the service's privacy, blocking and age restrictions.
    final posts = List<Post>.of(
      await context.read<SupabaseService>().fetchTimelinePosts(),
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts.take(50).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿一覧'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/', (route) => false),
            child: const Text('ホーム'),
          ),
        ],
      ),
      body: FutureBuilder<List<Post>>(
        future: _posts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snapshot.data ?? const <Post>[];
          if (snapshot.hasError || posts.isEmpty) {
            return Center(
              child: Text(
                snapshot.hasError
                    ? '投稿一覧を取得できませんでした。時間をおいて再度お試しください。'
                    : '現在、表示できる投稿がありません。',
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: RefreshIndicator(
                onRefresh: () async {
                  final refreshed = _load();
                  setState(() => _posts = refreshed);
                  await refreshed;
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text('『${post.bookTitle}』'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${post.username} · ★ ${post.rating} / 5'),
                            const SizedBox(height: 8),
                            Text(
                              post.hasSpoiler
                                  ? 'ネタバレを含む投稿です。詳細画面で内容を確認できます。'
                                  : post.reviewText,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).pushNamed('/posts/${Uri.encodeComponent(post.id)}'),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
