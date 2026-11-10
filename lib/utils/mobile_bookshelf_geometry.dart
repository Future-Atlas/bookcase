/// Exact mobile My Bookshelf layout proportions:
/// outer : book : gap : book : gap : book : outer = 2 : 8 : 1 : 8 : 1 : 8 : 2.
/// All horizontal dimensions therefore sum to 30 units of the viewport.
class MobileBookshelfGeometry {
  const MobileBookshelfGeometry(this.width);

  final double width;

  static const int columnCount = 3;
  static const double totalUnits = 30;

  double get unit => width / totalUnits;
  double get outerPadding => 2 * unit;
  double get interBookGap => unit;
  double get bookWidth => 8 * unit;

  // Preserve approximately the 2:3 book-cover silhouette, with a dedicated
  // description panel below the jacket and no internal card margins.
  double get coverHeight => bookWidth * 1.5;
  double get descriptionHeight => 104;
  double get cardHeight => coverHeight + descriptionHeight;
  double get childAspectRatio => bookWidth / cardHeight;
  double get coverHeightRatio => coverHeight / cardHeight;

  // Keep consistent spacing above/below the grid and between rows.
  double get verticalPadding => 2 * unit;
  double get rowGap => 2 * unit;
}
