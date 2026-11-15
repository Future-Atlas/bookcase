import 'package:flutter/material.dart';

/// Preserve the loaded Home screen while a reader opens the Usage Guide.
/// Keeping Home mounted avoids a burst of repeated catalog/API requests when
/// the reader returns. The guide is recreated for each visit, so all of its
/// expansion tiles start closed as documented.
class HomeGuideNavigationStack extends StatelessWidget {
  const HomeGuideNavigationStack({
    super.key,
    required this.showGuide,
    required this.home,
    required this.guide,
  });

  final bool showGuide;
  final Widget home;
  final Widget guide;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: showGuide ? 1 : 0,
      children: [
        home,
        if (showGuide) guide else const SizedBox.shrink(),
      ],
    );
  }
}
