import 'package:flutter/material.dart';

/// Consistent day cell borders on mobile and desktop.
/// Desktop retains the existing relative emphasis for today, but uses
/// three times the previous stroke width for both kinds of day.
BorderSide readingCalendarDayBorder({
  required Brightness brightness,
  required bool isToday,
  required bool isDesktop,
  required Color accentColor,
}) {
  return BorderSide(
    color: isToday
        ? accentColor
        : brightness == Brightness.dark
            ? Colors.white
            : Colors.black,
    width: (isToday ? 2.0 : 1.0) * (isDesktop ? 3.0 : 1.0),
  );
}
