import '../models/book.dart';

/// Centralized age-restriction checks used for externally sourced book data.
///
/// This client-side check is backed by a separate PostgreSQL trigger and RLS
/// policy for posts. Keeping both layers prevents accidental display in the UI
/// while ensuring that direct API access cannot bypass the age restriction.
class ContentSafetyService {
  const ContentSafetyService._();

  static const List<String> adultContentTerms = [
    '成人向け',
    '成人指定',
    '成人雑誌',
    '成年向け',
    '成年コミック',
    '成人コミック',
    '18禁',
    'r18',
    'r-18',
    'アダルト',
    'エロ本',
    'ポルノ',
    'hentai',
    'pornography',
    'pornographic',
    'adult magazine',
    'adults only',
    'sexually explicit',
  ];

  static final List<String> _normalizedAdultTerms = adultContentTerms
      .map(normalizeForMatching)
      .where((term) => term.isNotEmpty)
      .toSet()
      .toList(growable: false);

  static String normalizeForMatching(String source) {
    return source.toLowerCase().replaceAll(
      RegExp(r'[\s\u3000_\-‐‑‒–—―・･.／/]+'),
      '',
    );
  }

  static bool containsAdultContentTerms(Iterable<String> values) {
    final normalized = normalizeForMatching(values.join(' '));
    if (normalized.isEmpty) return false;
    return _normalizedAdultTerms.any(normalized.contains);
  }

  /// Add *verified* adult-only Rakuten Books genre IDs here. This list is
  /// intentionally empty until the official taxonomy is reviewed; categories
  /// such as BL or general comics are not uniformly age-restricted.
  /// Ancestor IDs match their descendant genres.
  static const Set<String> restrictedRakutenGenreIds = <String>{};

  static bool hasRestrictedRakutenGenre(
    Book book, {
    Set<String> restrictedGenreIds = restrictedRakutenGenreIds,
  }) {
    return restrictedGenreIds.any(book.belongsToRakutenGenre);
  }

  static bool isAdultBook(
    Book book, {
    Set<String> restrictedGenreIds = restrictedRakutenGenreIds,
  }) {
    return hasRestrictedRakutenGenre(
      book,
      restrictedGenreIds: restrictedGenreIds,
    ) || containsAdultContentTerms([
      book.title,
      book.author,
      book.publisher,
      book.genre,
      book.description,
    ]);
  }

  static bool isAdultSearchQuery(String query) {
    return containsAdultContentTerms([query]);
  }

  static List<Book> filterBooks(
    Iterable<Book> books, {
    required bool allowAdultContent,
    Set<String> restrictedGenreIds = restrictedRakutenGenreIds,
  }) {
    if (allowAdultContent) return List<Book>.of(books);
    return books
        .where(
          (book) => !isAdultBook(
            book,
            restrictedGenreIds: restrictedGenreIds,
          ),
        )
        .toList(growable: false);
  }

  static bool isAtLeast18(DateTime birthDate, {DateTime? onDate}) {
    final today = onDate ?? DateTime.now();
    var age = today.year - birthDate.year;
    final birthdayHasPassed =
        today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!birthdayHasPassed) age--;
    return age >= 18;
  }
}
