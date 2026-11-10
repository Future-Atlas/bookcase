import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/utils/mobile_bookshelf_geometry.dart';

void main() {
  test('three mobile shelf books respect exact 2:8:1:8:1:8:2 ratio', () {
    for (final width in [320.0, 375.0, 390.0, 430.0, 599.0]) {
      final grid = MobileBookshelfGeometry(width);
      final consumed = 2 * grid.outerPadding +
          3 * grid.bookWidth +
          2 * grid.interBookGap;
      expect(consumed, closeTo(width, 1e-8));
      expect(grid.outerPadding / grid.bookWidth, 2 / 8);
      expect(grid.interBookGap / grid.bookWidth, 1 / 8);
      expect(MobileBookshelfGeometry.columnCount, 3);
      expect(grid.rowGap, 2 * grid.unit);
    }
  });

  test('card height reserves the full portrait cover and book details', () {
    final grid = MobileBookshelfGeometry(390);
    expect(grid.coverHeight / grid.bookWidth, 1.5);
    expect(grid.descriptionHeight, greaterThan(80));
    expect(grid.coverHeightRatio,
        closeTo(1.5 * grid.bookWidth / grid.cardHeight, 1e-8));
    expect(grid.childAspectRatio,
        closeTo(grid.bookWidth / grid.cardHeight, 1e-8));
  });
}
