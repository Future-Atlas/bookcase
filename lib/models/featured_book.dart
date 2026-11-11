import 'book.dart';

class FeaturedBook {
  const FeaturedBook({
    required this.id,
    required this.book,
    required this.priority,
    required this.startsAt,
    required this.endsAt,
    required this.relatedScreenTitles,
  });

  final int id;
  final Book book;
  final int priority;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<String> relatedScreenTitles;

  factory FeaturedBook.fromJson(Map<String, dynamic> json) {
    final related = json['related_screen_titles'];
    return FeaturedBook(
      id: (json['id'] as num?)?.toInt() ?? 0,
      book: Book(
        id: json['book_id']?.toString() ?? '',
        isbn: json['book_id']?.toString() ?? '',
        title: json['book_title']?.toString() ?? '',
        author: json['book_author']?.toString() ?? '',
        publisher: json['book_publisher']?.toString() ?? '',
        pubDate: '',
        // Existing rows may include legacy provider-sourced snapshots with no
        // provenance or expiry. Never render them as current metadata.
        coverUrl: '',
        description: '',
      ),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? ''),
      relatedScreenTitles: related is List
          ? related
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}
