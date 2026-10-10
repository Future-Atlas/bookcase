import 'package:flutter/widgets.dart';

/// No ad inventory is rendered on non-web platforms.
class TimelineAdSlot extends StatelessWidget {
  const TimelineAdSlot({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
