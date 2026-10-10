// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Only the *asynchronous PC/SP switch tag* is supported here.
/// Until the official tag is issued and configured, no slot is displayed.
const bool _adMaxEnabled = bool.fromEnvironment(
  'NINJA_ADMAX_ENABLED',
  defaultValue: false,
);
const String _adMaxSwitchId = String.fromEnvironment(
  'NINJA_ADMAX_SWITCH_ID',
);

const String _viewType = 'sharemarium-ninja-admax-timeline';

class TimelineAdSlot extends StatelessWidget {
  const TimelineAdSlot({super.key});

  static bool _registered = false;

  static bool get _configured =>
      _adMaxEnabled &&
      RegExp(r'^[a-fA-F0-9]{24,64}$').hasMatch(_adMaxSwitchId);

  static void _registerFactory() {
    if (_registered) return;
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final root = html.DivElement()
        ..classes.add('sharemarium-admax-timeline-slot')
        ..setAttribute('data-sharemarium-admax-id', _adMaxSwitchId);
      root.style
        ..width = '100%'
        ..height = '250px'
        ..textAlign = 'center'
        ..overflow = 'hidden';

      final target = html.DivElement()
        ..classes.add('admax-switch')
        ..setAttribute('data-admax-id', _adMaxSwitchId);
      target.style
        ..display = 'inline-block'
        ..maxWidth = '100%';

      root.append(target);
      // Flutter inserts the platform view after factory creation.
      // The JS controller retries until the node is connected.
      Future<void>.delayed(Duration.zero, () {
        html.window.dispatchEvent(html.CustomEvent(
          'sharemarium:admax-slot-ready',
          detail: root,
        ));
      });
      return root;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_configured) return const SizedBox.shrink();
    _registerFactory();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Semantics(
        label: '広告',
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('広告', style: TextStyle(fontSize: 12)),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 250,
                  child: HtmlElementView(viewType: _viewType),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
