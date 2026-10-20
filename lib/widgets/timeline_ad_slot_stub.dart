import 'package:flutter/widgets.dart';

/// No advertising content is rendered on non-web platforms.
class TimelineAdSlot extends StatelessWidget {
  const TimelineAdSlot({
    super.key,
    required this.slotIndex,
    this.dismissible = false,
  });

  final int slotIndex;
  final bool dismissible;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
