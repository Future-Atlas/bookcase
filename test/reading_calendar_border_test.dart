import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/utils/reading_calendar_border.dart';

void main() {
  const accent = Color(0xFF7B45CD);

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final isDesktop in [false, true]) {
      test('calendar borders: ${brightness.name} / desktop=$isDesktop', () {
        final normal = readingCalendarDayBorder(
          brightness: brightness,
          isToday: false,
          isDesktop: isDesktop,
          accentColor: accent,
        );
        final today = readingCalendarDayBorder(
          brightness: brightness,
          isToday: true,
          isDesktop: isDesktop,
          accentColor: accent,
        );
        expect(normal.color,
            brightness == Brightness.dark ? Colors.white : Colors.black);
        expect(today.color, accent);
        expect(normal.width, isDesktop ? 3.0 : 1.0);
        expect(today.width, isDesktop ? 6.0 : 2.0);
      });
    }
  }
}
