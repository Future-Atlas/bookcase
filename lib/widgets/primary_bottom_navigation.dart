import 'package:flutter/material.dart';

/// Persistent primary navigation, shared by Home, Timeline, and My Page.
/// A Scaffold.bottomNavigationBar reserves its height so scrollable content
/// cannot be obscured by the footer.
class PrimaryBottomNavigation extends StatelessWidget {
  const PrimaryBottomNavigation({
    super.key,
    required this.accentColor,
    required this.selectedIndex,
    required this.onTimeline,
    required this.onHome,
    required this.onMyPage,
  });

  final Color accentColor;
  /// Timeline = 0, Home = 1, My Page = 2.
  final int selectedIndex;
  final VoidCallback onTimeline;
  final VoidCallback onHome;
  final VoidCallback onMyPage;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? Colors.black : Colors.white;
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: accentColor, width: 3),
        ),
        child: Row(
          children: [
            _item(
              0, 'タイムライン', onTimeline,
              const Text('▽', style: TextStyle(fontSize: 28, height: 1)),
            ),
            _item(1, 'ホーム', onHome, const Icon(Icons.home_outlined, size: 25)),
            _item(2, 'マイページ', onMyPage,
                const Icon(Icons.person_outline, size: 25)),
          ],
        ),
      ),
    );
  }

  Widget _item(int index, String label, VoidCallback onTap, Widget symbol) {
    final selected = selectedIndex == index;
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          key: ValueKey('primary-footer-${index == 0 ? 'timeline' : index == 1 ? 'home' : 'profile'}'),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(color: accentColor),
                child: DefaultTextStyle(
                  style: TextStyle(color: accentColor),
                  child: symbol,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
