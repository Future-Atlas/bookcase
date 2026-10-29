/// Rakuten Books genre restrictions for viewers under 18.
/// 
/// Only enter IDs that have been individually verified with the official
/// BooksGenre/Search API to describe exclusively 18+ content. Keep parent
/// categories that include general-audience books (e.g. BL, TL, comics)
/// unlisted. The "adult" facet on the Rakuten site is NOT a genre ID.
///
/// To register: '001xxxxxx': 'Verified genre name / review date / evidence'
/// The keys are 3-digit-hierarchy Rakuten *Books* IDs, kept as strings.
class RestrictedRakutenGenres {
  const RestrictedRakutenGenres._();

  static const Map<String, String> verifiedAdultOnly = <String, String>{
    // No independently verified 18+-only Books genre IDs as of 2026-10-29.
    // Add a verified ID with its name and evidence only after review.
  };

  static const Set<String> neverBlockBroadGenres = <String>{
    '001', // Books: contains all audiences
    '005', // Foreign books: contains all audiences
    '007', // Magazines: contains all audiences
  };

  static Set<String> get blockedIds =>
      verifiedAdultOnly.keys.toSet();
}
