import 'package:flutter/material.dart';

import '../models/profile_page_color.dart';

class ProfileColorBorder extends StatelessWidget {
  const ProfileColorBorder({
    super.key,
    required this.pageColorKey,
    required this.child,
  });

  final String? pageColorKey;
  final Widget child;

  static const double borderWidth = 2;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: ProfilePageColors.colorFor(pageColorKey),
          width: borderWidth,
        ),
      ),
      child: child,
    );
  }
}
