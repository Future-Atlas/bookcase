// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/widgets.dart';

const String _insetChangedEvent =
    'sharemarium:bottom-ad-viewport-inset-changed';
const String _insetRequestEvent =
    'sharemarium:bottom-ad-viewport-inset-request';

final ValueNotifier<double> _bottomAdInset = ValueNotifier<double>(0);
bool _listenerRegistered = false;

void _ensureInsetListener() {
  if (_listenerRegistered) return;
  _listenerRegistered = true;
  html.window.addEventListener(_insetChangedEvent, (event) {
    if (event is! html.CustomEvent || event.detail is! num) return;
    final inset = (event.detail as num).toDouble().clamp(0, 600).toDouble();
    if (_bottomAdInset.value != inset) {
      _bottomAdInset.value = inset;
    }
  });
  html.window.dispatchEvent(html.Event(_insetRequestEvent));
}

/// Keeps Flutter's scrollable viewport above the provider's fixed bottom ad.
/// The inset returns to zero as soon as the user closes that ad.
class BottomAdViewportInset extends StatefulWidget {
  const BottomAdViewportInset({super.key, required this.child});

  final Widget child;

  @override
  State<BottomAdViewportInset> createState() =>
      _BottomAdViewportInsetState();
}

class _BottomAdViewportInsetState extends State<BottomAdViewportInset> {
  @override
  void initState() {
    super.initState();
    _ensureInsetListener();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _bottomAdInset,
      child: widget.child,
      builder: (context, inset, child) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: inset),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
