import 'package:flutter/material.dart';

class Book {
  final String id;
  final String title;
  final String author;
  final String publisher;
  final String pubDate;
  final String isbn;
  final String coverUrl;
  final double ratingAvg;
  final int reviewCount;
  final String genre;
  /// The leaf Rakuten Books genre IDs supplied by the catalog, not search labels.
  /// An item can belong to multiple genres (slash-separated in the API).
  final List<String> rakutenGenreIds;
  final String description;
  final String rakutenAffiliateUrl;
  final int itemPrice;
  // Provenance of catalog values: rakuten, ndl, or unverified. This is
  // separate from permanent user-authored review data and ISBN identity.
  final bool adultContentFlag;
  final String ageRatingSource;
  final String languageCode;
  final String ndcCode;
  final String catalogSource;
  final DateTime? catalogFetchedAt;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.publisher,
    required this.pubDate,
    required this.isbn,
    required this.coverUrl,
    this.ratingAvg = 0.0,
    this.reviewCount = 0,
    this.genre = '',
    this.rakutenGenreIds = const [],
    this.description = '',
    this.rakutenAffiliateUrl = '',
    this.itemPrice = 0,
    this.adultContentFlag = false,
    this.ageRatingSource = 'unknown',
    this.languageCode = '',
    this.ndcCode = '',
    this.catalogSource = 'unverified',
    this.catalogFetchedAt,
  });

  /// Parse the Rakuten Books `booksGenreId` field without losing leading zeros.
  /// Ignore missing / malformed values rather than treating them as safe genres.
  static List<String> parseRakutenGenreIds(Object? value) {
    final text = value is Iterable
        ? value.map((part) => part.toString()).join('/')
        : (value?.toString() ?? '');
    final ids = <String>[];
    final seen = <String>{};
    for (final part in text.split('/')) {
      final id = part.trim();
      if (RegExp(r'^\d{3}(?:\d{3})*$').hasMatch(id) && seen.add(id)) {
        ids.add(id);
      }
    }
    return List<String>.unmodifiable(ids);
  }

  /// True for an exact genre ID or a child in its 3-digit hierarchy.
  /// E.g. `001004008` belongs to both `001` and `001004`.
  bool belongsToRakutenGenre(String genreId) {
    if (!RegExp(r'^\d{3}(?:\d{3})*$').hasMatch(genreId)) return false;
    return rakutenGenreIds.any(
      (id) => id == genreId ||
          (id.startsWith(genreId) &&
              id.length > genreId.length &&
              (id.length - genreId.length) % 3 == 0),
    );
  }

  // Factory from NDL JSON (simplified)
  factory Book.fromNdlJson(Map<String, dynamic> json) {
    final title = json['title'] ?? '不明なタイトル';
    final author = json['creator'] ?? '不明な著者';
    final publisher = json['publisher'] ?? '不明な出版社';
    final pubDate = json['dcdate'] ?? '';
    final isbn = json['isbn'] ?? '';
    return Book(
      id: isbn.isNotEmpty ? isbn : UniqueKey().toString(),
      title: title,
      author: author,
      publisher: publisher,
      pubDate: pubDate,
      isbn: isbn,
      coverUrl: '',
      genre: '',
      description: '',
      catalogSource: 'ndl',
      catalogFetchedAt: DateTime.now().toUtc(),
    );
  }

  // Factory from Rakuten JSON (simplified)
  factory Book.fromRakutenJson(Map<String, dynamic> json) {
    final title = json['title'] ?? '不明なタイトル';
    final rawAuthor = json['author'];
    final author = rawAuthor is List
        ? rawAuthor.join(', ')
        : rawAuthor?.toString() ?? '不明な著者';
    final publisher = json['publisherName'] ?? '不明な出版社';
    final pubDate = json['salesDate'] ?? '';
    final isbn = json['isbn'] ?? '';
    final coverUrl = json['largeImageUrl'] ?? '';
    final rawReviewAverage = json['reviewAverage'];
    final ratingAvg = rawReviewAverage is num
        ? rawReviewAverage.toDouble()
        : double.tryParse(rawReviewAverage?.toString() ?? '') ?? 0.0;
    final rawReviewCount = json['reviewCount'];
    final reviewCount = rawReviewCount is num
        ? rawReviewCount.toInt()
        : int.tryParse(rawReviewCount?.toString() ?? '') ?? 0;
    final rawItemPrice = json['itemPrice'];
    final itemPrice = rawItemPrice is num
        ? rawItemPrice.toInt()
        : int.tryParse(rawItemPrice?.toString() ?? '') ?? 0;
    final id = isbn.isNotEmpty ? isbn : UniqueKey().toString();
    return Book(
      id: id,
      title: title,
      author: author,
      publisher: publisher,
      pubDate: pubDate,
      isbn: isbn,
      coverUrl: coverUrl,
      ratingAvg: ratingAvg,
      rakutenAffiliateUrl: json['affiliateUrl'] as String? ?? '',
      reviewCount: reviewCount,
      genre: '',
      rakutenGenreIds: parseRakutenGenreIds(json['booksGenreId']),
      description: '',
      itemPrice: itemPrice,
      catalogSource: 'rakuten',
      catalogFetchedAt: DateTime.now().toUtc(),
    );
  }

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? publisher,
    String? pubDate,
    String? isbn,
    String? coverUrl,
    double? ratingAvg,
    int? reviewCount,
    String? genre,
    List<String>? rakutenGenreIds,
    String? description,
    String? rakutenAffiliateUrl,
    int? itemPrice,
    bool? adultContentFlag,
    String? ageRatingSource,
    String? languageCode,
    String? ndcCode,
    String? catalogSource,
    DateTime? catalogFetchedAt,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      publisher: publisher ?? this.publisher,
      pubDate: pubDate ?? this.pubDate,
      isbn: isbn ?? this.isbn,
      coverUrl: coverUrl ?? this.coverUrl,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      reviewCount: reviewCount ?? this.reviewCount,
      genre: genre ?? this.genre,
      rakutenGenreIds: rakutenGenreIds ?? this.rakutenGenreIds,
      description: description ?? this.description,
      rakutenAffiliateUrl: rakutenAffiliateUrl ?? this.rakutenAffiliateUrl,
      itemPrice: itemPrice ?? this.itemPrice,
      adultContentFlag: adultContentFlag ?? this.adultContentFlag,
      ageRatingSource: ageRatingSource ?? this.ageRatingSource,
      languageCode: languageCode ?? this.languageCode,
      ndcCode: ndcCode ?? this.ndcCode,
      catalogSource: catalogSource ?? this.catalogSource,
      catalogFetchedAt: catalogFetchedAt ?? this.catalogFetchedAt,
    );
  }
}
