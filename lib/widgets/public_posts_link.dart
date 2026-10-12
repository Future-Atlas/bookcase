import 'package:flutter/material.dart';

/// Direct navigation to the public post list.
///
 /// Keep this visible outside the service introduction so new visitors can
 /// recognize where to browse other readers' reviews.
class PublicPostsLink extends StatelessWidget {
  const PublicPostsLink({
    super.key,
    this.compact = false,
    this.foregroundColor,
  });

  final bool compact;
  final Color? foregroundColor;

  void _openPosts(BuildContext context) {
    Navigator.of(context).pushNamed('/posts');
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: '投稿一覧を見る',
        child: TextButton(
          key: const ValueKey('header-public-posts-link'),
          onPressed: () => _openPosts(context),
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '投稿一覧',
              maxLines: 1,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const ValueKey('home-public-posts-link'),
      onPressed: () => _openPosts(context),
      icon: const Icon(Icons.forum_outlined),
      label: const Text('投稿一覧を見る'),
    );
  }
}
