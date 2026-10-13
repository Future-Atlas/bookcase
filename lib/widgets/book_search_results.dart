import 'package:flutter/material.dart';
import '../models/book.dart';
import 'book_card.dart';
import 'timeline_ad_slot.dart';

/// Twenty books per loaded batch, with one advertisement after its first ten.
/// Narrow screens retain readable cards instead of forcing five tiny columns.
class BookSearchResults extends StatelessWidget {
  const BookSearchResults({
    super.key,
    required this.books,
    required this.onTap,
  });
  final List<Book> books;
  final ValueChanged<Book> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = bounds.maxWidth >= 900
          ? 5
          : bounds.maxWidth >= 680
          ? 4
          : bounds.maxWidth >= 460
          ? 3
          : 2;
      return Column(
        children: [
          for (var start = 0; start < books.length; start += 10) ...[
            if (start > 0) const SizedBox(height: 16),
            GridView.builder(
              key: ValueKey('search-books-$start'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.65,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: (books.length - start).clamp(0, 10),
              itemBuilder: (context, index) => BookCard(
                book: books[start + index],
                width: double.infinity,
                onTap: () => onTap(books[start + index]),
              ),
            ),
            if (start % 20 == 0 && start + 10 < books.length)
              TimelineAdSlot(
                key: ValueKey('search-ad-${start ~/ 20}'),
                slotIndex: start ~/ 20,
              ),
          ],
        ],
      );
    },
  );
}
