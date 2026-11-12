import 'social_models.dart';

class Post {
  final String id;
  final String profileId;
  final String bookId;
  final double rating;
  final String comment;
  final DateTime createdAt;
  final DateTime? editedAt;

  // Joined fields
  final String username;
  final String userAvatarUrl;
  final String profilePageColorKey;
  final String bookTitle;
  final String bookAuthor;
  final String bookCoverUrl;
  final String bookCoverSource;
  final bool isAgeRestricted;
  final bool isSpoiler;
  final Map<PostReactionType, int> reactionCounts;
  final PostReactionType? currentUserReaction;
  final int wantToReadCount;
  final bool wantedByCurrentUser;

  int get reactionsCount => reactionCounts.values.fold(0, (a, b) => a + b);
  double get reactionScore =>
      (reactionCounts[PostReactionType.like] ?? 0).toDouble() +
      (reactionCounts[PostReactionType.love] ?? 0) * 2.0 +
      (reactionCounts[PostReactionType.sad] ?? 0) * 0.5;
  bool get reactedByCurrentUser => currentUserReaction != null;
  bool get isEdited => editedAt != null;
  bool get hasSpoiler => isSpoiler || comment.trimLeft().startsWith('[ネタバレあり]');

  String get reviewText {
    final trimmed = comment.trimLeft();
    for (final prefix in const ['[ネタバレあり]', '[ネタバレなし]']) {
      if (trimmed.startsWith(prefix)) {
        return trimmed.substring(prefix.length).trimLeft();
      }
    }
    return comment;
  }

  Post({
    required this.id,
    required this.profileId,
    required this.bookId,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.editedAt,
    required this.username,
    required this.userAvatarUrl,
    this.profilePageColorKey = 'yellow',
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookCoverUrl,
    this.bookCoverSource = '',
    this.isAgeRestricted = false,
    this.isSpoiler = false,
    this.reactionCounts = const {},
    this.currentUserReaction,
    this.wantToReadCount = 0,
    this.wantedByCurrentUser = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // Handle nesting structures that come back from Supabase join queries (e.g. select: '*,profiles(*),books(*)')
    final profile = json['profiles'] as Map<String, dynamic>?;
    final book = json['books'] as Map<String, dynamic>?;

    final comment = json['comment']?.toString() ?? '';
    return Post(
      id: json['id'] ?? '',
      profileId: json['profile_id'] ?? '',
      bookId: json['book_id'] ?? '',
      rating: (json['rating'] ?? 0.0).toDouble(),
      comment: comment,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      editedAt: json['edited_at'] != null
          ? DateTime.tryParse(json['edited_at'].toString())
          : null,
      username: profile?['username'] ?? '匿名ユーザー',
      userAvatarUrl: profile?['avatar_url'] ?? '',
      profilePageColorKey: profile?['page_color']?.toString() ?? 'yellow',
      bookTitle: json['book_title'] ?? book?['title'] ?? '',
      bookAuthor: json['book_author'] ?? book?['author'] ?? '',
      bookCoverUrl: book?['cover_url'] ?? '',
      bookCoverSource: book?['cover_source']?.toString() ?? '',
      isAgeRestricted: json['is_age_restricted'] == true,
      isSpoiler:
          json['is_spoiler'] == true ||
          comment.trimLeft().startsWith('[ネタバレあり]'),
      reactionCounts: const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile_id': profileId,
      'book_id': bookId,
      'rating': rating,
      'comment': comment,
      'book_title': bookTitle,
      'book_author': bookAuthor,
      'is_age_restricted': isAgeRestricted,
      'is_spoiler': isSpoiler,
      'created_at': createdAt.toIso8601String(),
      'edited_at': editedAt?.toIso8601String(),
    };
  }

  Post copyWith({
    String? id,
    String? profileId,
    String? bookId,
    double? rating,
    String? comment,
    DateTime? createdAt,
    DateTime? editedAt,
    String? username,
    String? userAvatarUrl,
    String? profilePageColorKey,
    String? bookTitle,
    String? bookAuthor,
    String? bookCoverUrl,
    String? bookCoverSource,
    bool? isAgeRestricted,
    bool? isSpoiler,
    Map<PostReactionType, int>? reactionCounts,
    PostReactionType? currentUserReaction,
    bool clearCurrentUserReaction = false,
    int? wantToReadCount,
    bool? wantedByCurrentUser,
  }) {
    return Post(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      bookId: bookId ?? this.bookId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      username: username ?? this.username,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      profilePageColorKey: profilePageColorKey ?? this.profilePageColorKey,
      bookTitle: bookTitle ?? this.bookTitle,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      bookCoverUrl: bookCoverUrl ?? this.bookCoverUrl,
      bookCoverSource: bookCoverSource ?? this.bookCoverSource,
      isAgeRestricted: isAgeRestricted ?? this.isAgeRestricted,
      isSpoiler: isSpoiler ?? this.isSpoiler,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      currentUserReaction: clearCurrentUserReaction
          ? null
          : currentUserReaction ?? this.currentUserReaction,
      wantToReadCount: wantToReadCount ?? this.wantToReadCount,
      wantedByCurrentUser: wantedByCurrentUser ?? this.wantedByCurrentUser,
    );
  }

  /// Returns the state shown immediately after the current user taps a
  /// reaction. Persisting it to the backend is handled separately.
  Post withToggledReaction(PostReactionType reaction) {
    final nextCounts = Map<PostReactionType, int>.from(reactionCounts);
    final previousReaction = currentUserReaction;

    if (previousReaction != null) {
      final previousCount = nextCounts[previousReaction] ?? 0;
      if (previousCount <= 1) {
        nextCounts.remove(previousReaction);
      } else {
        nextCounts[previousReaction] = previousCount - 1;
      }
    }

    final nextReaction = previousReaction == reaction ? null : reaction;
    if (nextReaction != null) {
      nextCounts[nextReaction] = (nextCounts[nextReaction] ?? 0) + 1;
    }

    return copyWith(
      reactionCounts: nextCounts,
      currentUserReaction: nextReaction,
      clearCurrentUserReaction: nextReaction == null,
    );
  }

  Post withToggledWantToRead() {
    return copyWith(
      wantToReadCount: wantedByCurrentUser
          ? (wantToReadCount - 1).clamp(0, 1 << 31).toInt()
          : wantToReadCount + 1,
      wantedByCurrentUser: !wantedByCurrentUser,
    );
  }
}
