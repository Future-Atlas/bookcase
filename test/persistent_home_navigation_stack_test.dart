import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/persistent_home_navigation_stack.dart';

class _CounterHome extends StatefulWidget {
  const _CounterHome({required this.onInit, required this.onDispose});
  final VoidCallback onInit;
  final VoidCallback onDispose;

  @override
  State<_CounterHome> createState() => _CounterHomeState();
}

class _CounterHomeState extends State<_CounterHome> {
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
  Widget build(BuildContext context) => const Text('cached books');
}

void main() {
  testWidgets('returning Home from any other screen keeps the same book list',
      (tester) async {
    var initialized = 0;
    var disposed = 0;
    var showHome = true;
    var showGuide = false;
    var destination = 'My Page';
    var account = 'reader-a';
    late StateSetter update;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return PersistentHomeNavigationStack(
          showHome: showHome,
          showGuide: showGuide,
          cacheKey: account,
          home: _CounterHome(
            onInit: () => initialized++,
            onDispose: () => disposed++,
          ),
          guide: const Text('Usage Guide'),
          other: Text(destination),
        );
      }),
    ));
    expect(initialized, 1);
    expect(disposed, 0);

    for (final screen in ['My Page', 'Settings', 'Other user', 'Help']) {
      update(() {
        showHome = false;
        destination = screen;
      });
      await tester.pump();
      expect(find.text(screen), findsOneWidget);
      expect(initialized, 1);
      expect(disposed, 0);

      update(() => showHome = true);
      await tester.pump();
      expect(find.text('cached books'), findsOneWidget);
      expect(initialized, 1, reason: 'Home must never re-fetch on return');
      expect(disposed, 0);
    }

    update(() => showGuide = true);
    await tester.pump();
    expect(find.text('Usage Guide'), findsOneWidget);
    update(() => showGuide = false);
    await tester.pump();
    expect(initialized, 1);
    expect(disposed, 0);

    update(() {
      showHome = false;
      destination = 'Settings';
      account = 'reader-b';
    });
    await tester.pump();
    expect(disposed, 1, reason: 'Sign-out must dispose private cached home');

    update(() => showHome = true);
    await tester.pump();
    expect(initialized, 2, reason: 'New account must fetch its own Home');
  });

  testWidgets('does not prefetch Home when launched at a secondary screen',
      (tester) async {
    var initialized = 0;
    var showHome = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return PersistentHomeNavigationStack(
          showHome: showHome,
          showGuide: false,
          cacheKey: 'reader',
          home: _CounterHome(
            onInit: () => initialized++,
            onDispose: () {},
          ),
          guide: const Text('Guide'),
          other: const Text('Settings'),
        );
      }),
    ));
    expect(initialized, 0);
    update(() => showHome = true);
    await tester.pump();
    expect(initialized, 1);
  });
}
