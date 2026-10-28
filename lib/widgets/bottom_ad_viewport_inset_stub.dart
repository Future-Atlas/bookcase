import 'package:flutter/widgets.dart';

/// Non-web platforms do not render the provider's fixed bottom advertisement.
class BottomAdViewportInset extends StatelessWidget {
  const BottomAdViewportInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
