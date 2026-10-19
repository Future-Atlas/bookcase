import 'package:flutter/material.dart';

/// Direct navigation to the public post list.
///
/// Keep this visible outside the service introduction so new visitors can
/// recognize where to browse other readers' reviews.
class PublicPostsLink extends StatelessWidget {
  const PublicPostsLink({
    super.key,
    this.compact = false,
    this.dense = false,
    this.sectionHeading = false,
    this.foregroundColor,
  });

  final bool compact;
  final bool dense;
  final bool sectionHeading;
  final Color? foregroundColor;

  void _openPosts(BuildContext context) {
    Navigator.of(context).pushNamed('/posts');
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: 'タイムラインを見る',
        child: TextButton(
          key: const ValueKey('header-public-posts-link'),
          onPressed: () => _openPosts(context),
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor,
            padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 2),
            minimumSize: Size(0, dense ? 34 : 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'タイムライン',
              maxLines: 1,
              style: TextStyle(
                fontSize: dense ? 10 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    if (sectionHeading) {
      return TextButton.icon(
        key: const ValueKey('home-timeline-heading-link'),
        onPressed: () => _openPosts(context),
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.forum_outlined, size: 20),
        label: const Text(
          'タイムライン',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const ValueKey('home-public-posts-link'),
      onPressed: () => _openPosts(context),
      style: OutlinedButton.styleFrom(foregroundColor: foregroundColor),
      icon: const Icon(Icons.forum_outlined),
      label: const Text('タイムラインを見る'),
    );
  }
}
