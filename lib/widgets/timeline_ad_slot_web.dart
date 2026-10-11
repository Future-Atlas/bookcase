// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'timeline_ad_policy.dart';

const String _viewTypePrefix = 'sharemarium-ninja-admax-timeline';

/// Flutter Web-only inline advertisement. The publisher's exact synchronous
/// tag runs in a separate srcdoc iframe after route/entitlement verification.
/// Never insert the synchronous script into the running Flutter document.
class TimelineAdSlot extends StatelessWidget {
  const TimelineAdSlot({super.key, required this.slotIndex});

  final int slotIndex;
  static final Set<int> _registered = <int>{};

  static String _viewType(int index) => '$_viewTypePrefix-$index';

  static void _registerFactory(int index) {
    if (!_registered.add(index)) return;

    ui_web.platformViewRegistry.registerViewFactory(_viewType(index), (
      int viewId,
    ) {
      final root = html.DivElement()
        ..classes.add('sharemarium-admax-timeline-slot')
        ..setAttribute('data-sharemarium-admax-slot-index', '$index');
      root.style
        ..width = '100%'
        ..height = '250px'
        ..textAlign = 'center'
        ..overflow = 'hidden';

      final target = html.DivElement()
        ..classes.add('admax-inline-target');
      target.style
        ..width = '100%'
        ..height = '250px';

      root.append(target);
      // Flutter connects the platform view after factory creation.
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
    if (!timelineAdEnabled || slotIndex < 0 ||
        slotIndex >= timelineMaximumAdsPerPage) {
      return const SizedBox.shrink();
    }
    _registerFactory(slotIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Semantics(
            label: '広告',
            container: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('広告', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 250,
                      child: HtmlElementView(viewType: _viewType(slotIndex)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
