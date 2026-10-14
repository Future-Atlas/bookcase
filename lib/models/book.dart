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
  final String description;
  final String rakutenAffiliateUrl;

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
    this.description = '',
    this.rakutenAffiliateUrl = '',
  });

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
      description: '',
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
    String? description,
    String? rakutenAffiliateUrl,
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
      description: description ?? this.description,
      rakutenAffiliateUrl: rakutenAffiliateUrl ?? this.rakutenAffiliateUrl,
    );
  }
}
