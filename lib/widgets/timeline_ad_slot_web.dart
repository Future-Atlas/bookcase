// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'timeline_ad_policy.dart';
import '../config/app_environment.dart';

const String _viewTypePrefix = 'sharemarium-ninja-admax-native';
const String _entitlementChangedEvent = 'sharemarium:admax-entitlement-changed';
const String _entitlementRequestEvent = 'sharemarium:admax-entitlement-request';

final ValueNotifier<bool> _adEntitlementAllowed = ValueNotifier<bool>(false);
bool _entitlementListenerRegistered = false;

void _ensureEntitlementListener() {
  if (_entitlementListenerRegistered) return;
  _entitlementListenerRegistered = true;
  html.window.addEventListener(_entitlementChangedEvent, (event) {
    final allowed = event is html.CustomEvent && event.detail == true;
    if (_adEntitlementAllowed.value != allowed) {
      _adEntitlementAllowed.value = allowed;
    }
  });
  html.window.dispatchEvent(html.Event(_entitlementRequestEvent));
}

/// Actual DOM slot for the Ninja AdMax asynchronous SPA SDK.
/// Neither the synchronous /s/ tag nor app-created iframes are used.
class TimelineAdSlot extends StatefulWidget {
  const TimelineAdSlot({super.key, required this.slotIndex});

  final int slotIndex;
  @override
  State<TimelineAdSlot> createState() => _TimelineAdSlotState();
}

class _TimelineAdSlotState extends State<TimelineAdSlot> {
  int get slotIndex => widget.slotIndex;
  String get _dismissKey => 'sharemarium-ad-dismissed-$slotIndex';
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    try {
      _dismissed = html.window.sessionStorage[_dismissKey] == '1';
    } catch (_) {}
  }

  void _dismiss() {
    try {
      html.window.sessionStorage[_dismissKey] = '1';
    } catch (_) {}
    setState(() => _dismissed = true);
  }

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
        ..setAttribute(
          'data-sharemarium-admax-async-type',
          ninjaAdmaxAsyncType,
        );
      root.style
        ..setProperty('contain', 'layout paint')
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
        html.window.dispatchEvent(
          html.CustomEvent('sharemarium:admax-slot-ready', detail: root),
        );
      });
      return root;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (AppEnvironmentConfig.current == AppEnvironment.staging) {
      return Container(
        key: ValueKey('staging-ad-$slotIndex'),
        width: double.infinity,
        height: 140,
        margin: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFF1D600)),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Text('広告（検証用表示・配信なし）'),
      );
    }
    if (!timelineAdReady || slotIndex < 0) {
      return const SizedBox.shrink();
    }
    _ensureEntitlementListener();

    return ValueListenableBuilder<bool>(
      valueListenable: _adEntitlementAllowed,
      builder: (context, allowed, child) {
        if (!allowed) return const SizedBox.shrink();
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
                    border: Border.all(color: const Color(0xFFF1D600)),
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
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '広告',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              tooltip: 'この広告を閉じる',
                              onPressed: _dismiss,
                              icon: const Icon(Icons.close, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: ninjaAdmaxAsyncType == 'banner'
                              ? 90.0
                              : 250.0,
                          child: HtmlElementView(
                            viewType: _viewType(slotIndex),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
