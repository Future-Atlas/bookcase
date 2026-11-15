import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/home_guide_navigation_stack.dart';

class HomeLifecycleProbe extends StatefulWidget {
  const HomeLifecycleProbe({
    super.key,
    required this.onInit,
    required this.onDispose,
  });
  final VoidCallback onInit;
  final VoidCallback onDispose;

  @override
  State<HomeLifecycleProbe> createState() => _HomeLifecycleProbeState();
}

class _HomeLifecycleProbeState extends State<HomeLifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('loaded home');
}

void main() {
  testWidgets('guide does not reload home, and guide resets on each visit', (tester) async {
    var homeInitCount = 0;
    var homeDisposeCount = 0;
    var showGuide = false;
    late StateSetter setRootState;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          setRootState = setState;
          return HomeGuideNavigationStack(
            showGuide: showGuide,
            home: HomeLifecycleProbe(
              onInit: () => homeInitCount++,
              onDispose: () => homeDisposeCount++,
            ),
            guide: const Text('guide'),
          );
        },
      ),
    ));
    expect(homeInitCount, 1);

    setRootState(() => showGuide = true);
    await tester.pump();
    expect(find.text('guide'), findsOneWidget);
    expect(homeInitCount, 1);
    expect(homeDisposeCount, 0);

    setRootState(() => showGuide = false);
    await tester.pump();
    expect(find.text('loaded home'), findsOneWidget);
    expect(homeInitCount, 1);
    expect(homeDisposeCount, 0);
    expect(find.text('guide'), findsNothing);

    setRootState(() => showGuide = true);
    await tester.pump();
    expect(find.text('guide'), findsOneWidget);
    expect(homeInitCount, 1);
  });
}
