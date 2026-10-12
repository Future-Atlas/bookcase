// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'timeline_ad_policy.dart';

const String _viewTypePrefix = 'sharemarium-ninja-admax-native';

/// Actual DOM slot for the Ninja AdMax asynchronous SPA SDK.
/// Neither the synchronous /s/ tag nor app-created iframes are used.
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
        ..setAttribute('data-sharemarium-admax-slot-index', '$index')
        ..setAttribute('data-sharemarium-admax-async-id', ninjaAdmaxAsyncId)
        ..setAttribute('data-sharemarium-admax-async-type', ninjaAdmaxAsyncType);
      root.style
        ..width = '100%'
        ..height = ninjaAdmaxAsyncType == 'banner' ? '90px' : '250px'
        ..overflowX = ninjaAdmaxAsyncType == 'banner' ? 'auto' : 'visible'
        ..textAlign = 'center';

      final target = html.DivElement()
        ..classes.add(
          ninjaAdmaxAsyncType == 'switch' ? 'admax-switch' : 'admax-ads',
        )
        ..setAttribute('data-admax-id', ninjaAdmaxAsyncId);
      target.style
        ..display = 'inline-block'
        ..width = ninjaAdmaxAsyncType == 'banner' ? '728px' : '100%'
        ..height = ninjaAdmaxAsyncType == 'banner' ? '90px' : '250px';

      root.append(target);
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
    if (!timelineAdReady || slotIndex < 0) {
      return const SizedBox.shrink();
    }
    _registerFactory(slotIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
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
                      height: ninjaAdmaxAsyncType == 'banner' ? 90.0 : 250.0,
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
