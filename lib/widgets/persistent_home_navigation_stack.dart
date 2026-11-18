import 'package:flutter/material.dart';

import 'home_guide_navigation_stack.dart';

/// Keeps the Home book catalog mounted across *all* in-shell destinations.
///
/// Previously, only the Usage Guide preserved Home. Visiting My Page,
/// Settings, Help, or another user's profile destroyed BookListScreen;
/// returning then restarted every external catalog request, frequently
/// leading to transient empty/error sections. Secondary destinations remain
/// disposable, while the first successfully opened Home is kept in memory.
///
/// The cacheKey must change when the signed-in account changes so that
/// personalized posts and age-restricted material never survive sign-out.
class PersistentHomeNavigationStack extends StatefulWidget {
  const PersistentHomeNavigationStack({
    super.key,
    required this.showHome,
    required this.showGuide,
    required this.cacheKey,
    required this.home,
    required this.guide,
    required this.other,
  });

  final bool showHome;
  final bool showGuide;
  final Object cacheKey;
  final Widget home;
  final Widget guide;
  final Widget other;

  @override
  State<PersistentHomeNavigationStack> createState() =>
      _PersistentHomeNavigationStackState();
}

class _PersistentHomeNavigationStackState
    extends State<PersistentHomeNavigationStack> {
  late bool _hasOpenedHome = widget.showHome;

  @override
  void didUpdateWidget(covariant PersistentHomeNavigationStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      // A new user must never inherit the prior user's cached home.
      _hasOpenedHome = widget.showHome;
    } else if (widget.showHome) {
      _hasOpenedHome = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.showHome ? 0 : 1,
      children: [
        if (_hasOpenedHome)
          KeyedSubtree(
            key: ValueKey(widget.cacheKey),
            child: HomeGuideNavigationStack(
              showGuide: widget.showGuide,
              home: widget.home,
              guide: widget.guide,
            ),
          )
        else
          const SizedBox.shrink(),
        if (widget.showHome) const SizedBox.shrink() else widget.other,
      ],
    );
  }
}
