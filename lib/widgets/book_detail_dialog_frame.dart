import 'package:flutter/material.dart';

class BookDetailDialogFrame extends StatelessWidget {
  const BookDetailDialogFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final closeColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Dialog(
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.none,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 22, left: 22),
            child: Material(
              color: const Color(0xFFE6E6E6),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: child,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              shape: CircleBorder(
                side: const BorderSide(color: Color(0xFFD00303), width: 2),
              ),
              child: IconButton(
                key: const ValueKey('book-detail-close-button'),
                tooltip: '書籍情報を閉じる',
                onPressed: () => Navigator.of(context).pop(),
                color: closeColor,
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
