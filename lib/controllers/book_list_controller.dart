import 'dart:async';

import 'package:flutter/material.dart';
import '../models/book.dart';
import '../api/book_catalog_lookup.dart';
import '../repositories/book_repository.dart';
import '../models/post.dart';
import '../models/post_reply.dart';
import '../models/social_models.dart';
import '../models/user_profile.dart';
import '../services/content_safety_service.dart';
import '../services/supabase_service.dart';

class BookListController extends ChangeNotifier {
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';
  Timer? _searchDebounce;
  bool isLoading = true;
  bool isLoadingRecommended = true;
  bool isLoadingJapanese = true;
  bool isLoadingWestern = true;
  bool isLoadingPopular = true;
  bool isLoadingTimeline = true;

  bool isSearching = false;
  // Invalidate in-flight searches as soon as input changes, even if the
  // user changes from A to B and back to A before the first request finishes.
  int _searchGeneration = 0;
  bool hasMoreSearch = true;
  bool searchTemporarilyUnavailable = false;
  int searchPage = 1;
  List<Book> searchResults = [];
  List<UserProfile> userSearchResults = [];
  bool userSearchMode = false;
  final Set<String> _searchResultIds = <String>{};

  List<Book> get visibleSearchResults => searchResults;

  bool get canLoadMoreSearchResults => hasMoreSearch;

  // ジャンルごとに「リスト」「現在のページ」「まだ続きがあるか」を独立して管理
  List<Book> recommendedBooks = [];
  int recommendedPage = 1;
  bool hasMoreRecommended = true;
  bool isLoadingMoreRecommended = false;
  final Map<int, List<Book>> _recommendedPageCache = {};
  bool _recommendedReachedEnd = false;
  bool get canLoadPreviousRecommended => recommendedPage > 1;

  List<Book> japaneseBooks = [];
  int japanesePage = 1;
  bool hasMoreJapanese = true;
  bool isLoadingMoreJapanese = false;
  final Map<int, List<Book>> _japanesePageCache = {};
  bool _japaneseReachedEnd = false;
  bool get canLoadPreviousJapanese => japanesePage > 1;

  List<Book> westernBooks = [];
  int westernPage = 1;
  bool hasMoreWestern = true;
  bool isLoadingMoreWestern = false;
  final Map<int, List<Book>> _westernPageCache = {};
  bool _westernReachedEnd = false;
  bool get canLoadPreviousWestern => westernPage > 1;

  List<Book> popularBooks = [];
  int popularPage = 1;
  bool hasMorePopular = true;
  bool isLoadingMorePopular = false;
  final Map<int, List<Book>> _popularPageCache = {};
  bool _popularReachedEnd = false;
  bool get canLoadPreviousPopular => popularPage > 1;

  List<Book> featuredBooks = [];
  bool isLoadingFeatured = true;
  int _featuredLookupGeneration = 0;

  // タイムライン用
  List<Post> timelinePosts = [];
  Map<String, List<PostReply>> timelineReplies = {};
  bool _allowAdultContent = false;

  BookRepository _catalogRepository = BookRepository();

  BookRepository get _repository => _catalogRepository;

  Post? toggleTimelineReactionOptimistically(
    String postId,
    PostReactionType reaction,
  ) {
    final index = timelinePosts.indexWhere((post) => post.id == postId);
    if (index < 0) return null;

    final previous = timelinePosts[index];
    final updatedPosts = List<Post>.from(timelinePosts);
    updatedPosts[index] = previous.withToggledReaction(reaction);
    timelinePosts = updatedPosts;
    notifyListeners();
    return previous;
  }

  Post? toggleTimelineWantToReadOptimistically(String postId) {
    final index = timelinePosts.indexWhere((post) => post.id == postId);
    if (index < 0) return null;
    final previous = timelinePosts[index];
    final updatedPosts = List<Post>.from(timelinePosts);
    updatedPosts[index] = previous.withToggledWantToRead();
    timelinePosts = updatedPosts;
    notifyListeners();
    return previous;
  }

  void restoreTimelinePost(Post previous) {
    final index = timelinePosts.indexWhere((post) => post.id == previous.id);
    if (index < 0) return;

    final restoredPosts = List<Post>.from(timelinePosts);
    restoredPosts[index] = previous;
    timelinePosts = restoredPosts;
    notifyListeners();
  }

  // 初期化
  bool _timelineOnly = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    // Provider requests can finish after sign-out or navigation reset.
    if (!_disposed) super.notifyListeners();
  }

  void initialize(BuildContext context, {bool timelineOnly = false}) {
    _timelineOnly = timelineOnly;
    _loadData(context);
    searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _featuredLookupGeneration++;
    searchController.removeListener(_onSearchChanged);
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchGeneration++;
    _searchDebounce?.cancel();
    final value = searchController.value;
    searchQuery = value.text.trim();

    // Japanese IMEs notify listeners while the user is still converting text.
    // Searching those transient values wastes the shared catalogue quota and
    // can make the final, committed query appear to return no results.
    if (isComposingSearchInput(value)) {
      isSearching = false;
      searchTemporarilyUnavailable = false;
      notifyListeners();
      return;
    }

    if (searchQuery.isEmpty) {
      searchTemporarilyUnavailable = false;
      isSearching = false;
      hasMoreSearch = true;
      searchPage = 1;
      searchResults = [];
      userSearchResults = [];
      _searchResultIds.clear();
      notifyListeners();
      return;
    }

    searchTemporarilyUnavailable = false;
    isSearching = true;
    notifyListeners();

    _searchDebounce = Timer(const Duration(milliseconds: 750), () {
      if (userSearchMode) {
        _searchUsers();
      } else {
        _searchBooks(reset: true);
      }
    });
  }

  @visibleForTesting
  static bool isComposingSearchInput(TextEditingValue value) =>
      value.composing.isValid && !value.composing.isCollapsed;

  void setUserSearchMode(bool enabled) {
    if (userSearchMode == enabled) return;
    _searchGeneration++;
    userSearchMode = enabled;
    _searchDebounce?.cancel();
    isSearching = false;
    hasMoreSearch = true;
    searchTemporarilyUnavailable = false;
    searchPage = 1;
    searchResults = [];
    userSearchResults = [];
    _searchResultIds.clear();
    searchQuery = searchController.text.trim();
    notifyListeners();
    if (searchQuery.isEmpty) return;
    isSearching = true;
    notifyListeners();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (userSearchMode) {
        _searchUsers();
      } else {
        _searchBooks(reset: true);
      }
    });
  }

  Future<void> _searchUsers() async {
    final query = searchQuery.trim();
    if (query.isEmpty || !userSearchMode) {
      isSearching = false;
      notifyListeners();
      return;
    }

    isSearching = true;
    notifyListeners();
    try {
      final results = await SupabaseService().searchProfiles(query);
      if (!userSearchMode || query != searchQuery.trim()) return;
      userSearchResults = results;
    } finally {
      if (userSearchMode && query == searchQuery.trim()) {
        isSearching = false;
        notifyListeners();
      }
    }
  }

  Future<void> _searchBooks({required bool reset}) async {
    final generation = _searchGeneration;
    final query = searchQuery.trim();
    if (query.isEmpty || userSearchMode) {
      isSearching = false;
      notifyListeners();
      return;
    }

    if (reset) {
      hasMoreSearch = true;
      searchTemporarilyUnavailable = false;
      searchPage = 1;
      searchResults = [];
      _searchResultIds.clear();
    } else if (!hasMoreSearch || isSearching) {
      return;
    }

    isSearching = true;
    notifyListeners();

    try {
      final requestedPage = searchPage;
      final batch = await _repository.searchBooksPage(
        query,
        page: requestedPage,
        count: 10,
      );

      // 入力中に別の検索が始まった場合は、古い結果を画面へ反映しない。
      if (generation != _searchGeneration ||
          userSearchMode || query != searchQuery.trim()) return;
      if (batch.temporarilyUnavailable) {
        searchTemporarilyUnavailable = true;
        // Keep the last successful page and permit retrying the failed page.
        hasMoreSearch = true;
        return;
      }
      searchTemporarilyUnavailable = false;

      for (final book in batch.books) {
        if (_searchResultIds.add(book.id)) {
          searchResults.add(book);
        }
      }

      searchPage = requestedPage + 1;
      hasMoreSearch = batch.hasMore;
    } catch (_) {
      if (generation == _searchGeneration &&
          !userSearchMode && query == searchQuery.trim()) {
        searchTemporarilyUnavailable = true;
        hasMoreSearch = true;
      }
    } finally {
      if (generation == _searchGeneration &&
          !userSearchMode && query == searchQuery.trim()) {
        isSearching = false;
        notifyListeners();
      }
    }
  }

  Future<void> retrySearchBooks() async {
    if (searchQuery.isEmpty || userSearchMode || isSearching) return;
    // A failed load-more should NOT throw away the already displayed books.
    await _searchBooks(reset: searchResults.isEmpty);
  }

  Future<void> loadMoreSearchResults() async {
    if (userSearchMode || searchQuery.isEmpty || isSearching) return;
    if (!hasMoreSearch) return;
    await _searchBooks(reset: false);
  }

  // Curated ISBN, title and order are durable; provider artwork and synopsis
  // are short-lived. Resolve them only in memory for the current screen.
  // On API failure the existing curated book entry remains available.
  Future<void> _hydrateFeaturedBooks(int generation) async {
    final snapshot = List<Book>.of(featuredBooks);
    for (final original in snapshot) {
      if (generation != _featuredLookupGeneration) return;
      final normalizedId = (original.isbn.isNotEmpty
              ? original.isbn
              : original.id)
          .replaceAll('-', '');
      if (!RegExp(r'^(?:\d{13}|\d{9}[\dXx])$').hasMatch(normalizedId)) {
        continue;
      }
      Book? fresh;
      try {
        fresh = await const BookCatalogLookup().fetchById(
          normalizedId, enrichNdl: true,
        );
      } catch (_) {
        continue;
      }
      if (generation != _featuredLookupGeneration) return;
      if (fresh == null || fresh.isbn.replaceAll('-', '') != normalizedId) {
        continue;
      }
      final index = featuredBooks.indexWhere((book) => book.id == original.id);
      if (index < 0) continue;
      final hydrated = original.copyWith(
        coverUrl: fresh.coverUrl.trim().isNotEmpty
            ? fresh.coverUrl
            : original.coverUrl,
        coverSource: fresh.coverUrl.trim().isNotEmpty
            ? fresh.coverSource
            : original.coverSource,
        coverAttributionUrl: fresh.coverAttributionUrl,
        description: fresh.description,
        rakutenAffiliateUrl: fresh.rakutenAffiliateUrl,
        catalogSource: fresh.catalogSource,
        catalogFetchedAt: fresh.catalogFetchedAt,
      );
      if (!_allowAdultContent && ContentSafetyService.isAdultBook(hydrated)) {
        featuredBooks = List<Book>.of(featuredBooks)..removeAt(index);
      } else {
        featuredBooks = List<Book>.of(featuredBooks)..[index] = hydrated;
      }
      notifyListeners();
    }
  }

  Future<void> _loadData(BuildContext context) async {
    if (_timelineOnly) {
      isLoadingTimeline = true;
      notifyListeners();
      await _loadTimeline();
      return;
    }
    isLoading = true;
    isLoadingRecommended = true;
    isLoadingJapanese = true;
    isLoadingWestern = true;
    isLoadingPopular = true;
    isLoadingFeatured = true;
    isLoadingTimeline = true;
    notifyListeners();

    // Keep previously fetched Home cards visible during subsequent refreshes.
    // A transient catalog failure must not replace them with an empty state.
    bool canViewAdult;
    try {
      canViewAdult = await SupabaseService().canViewAdultContent();
    } catch (_) {
      canViewAdult = _allowAdultContent;
    }
    final accessChanged = _allowAdultContent != canViewAdult;
    _allowAdultContent = canViewAdult;
    if (accessChanged) {
      // Never retain adult-visible cards when view permissions change.
      _catalogRepository = BookRepository(allowAdultContent: canViewAdult);
      recommendedPage = japanesePage = westernPage = popularPage = 1;
      hasMoreRecommended = hasMoreJapanese = hasMoreWestern = hasMorePopular = true;
      _recommendedPageCache.clear();
      _japanesePageCache.clear();
      _westernPageCache.clear();
      _popularPageCache.clear();
      _recommendedReachedEnd = false;
      _japaneseReachedEnd = false;
      _westernReachedEnd = false;
      _popularReachedEnd = false;
      recommendedBooks = [];
      japaneseBooks = [];
      westernBooks = [];
      popularBooks = [];
      featuredBooks = [];
      timelinePosts = [];
      timelineReplies = {};
      notifyListeners();
    }
    final repository = _repository;
    final featuredGeneration = ++_featuredLookupGeneration;

    try {
      final featured = await SupabaseService().fetchFeaturedBooks();
      featuredBooks = featured
          .map((item) => item.book)
          .where(
            (book) =>
                _allowAdultContent || !ContentSafetyService.isAdultBook(book),
          )
          .toList(growable: false);
    } catch (_) {
      // Preserve any previous featured covers when the API is unavailable.
    } finally {
      isLoadingFeatured = false;
      notifyListeners();
    }
    if (featuredBooks.isNotEmpty) {
      unawaited(_hydrateFeaturedBooks(featuredGeneration));
    }

    Future<void> loadRecommended() async {
      try {
        final books = await repository.fetchBooksByGenre(
          '新着',
          page: recommendedPage,
        );
        // A provider can silently return [] on a transient 429/5xx. Keep
        // the last successful page and its pagination cursor in that case.
        if (books.isNotEmpty || recommendedBooks.isEmpty) {
          recommendedBooks = books;
          _recommendedPageCache[recommendedPage] = books;
          _recommendedReachedEnd = books.isEmpty ||
              !repository.hasMoreHomeBooks('新着');
          hasMoreRecommended = !_recommendedReachedEnd;
        }
      } catch (_) {
        if (recommendedBooks.isEmpty) hasMoreRecommended = false;
      } finally {
        isLoadingRecommended = false;
        notifyListeners();
      }
    }

    Future<void> loadJapanese() async {
      try {
        final books = await repository.fetchBooksByGenre(
          '和書',
          page: japanesePage,
        );
        // A provider can silently return [] on a transient 429/5xx. Keep
        // the last successful page and its pagination cursor in that case.
        if (books.isNotEmpty || japaneseBooks.isEmpty) {
          japaneseBooks = books;
          _japanesePageCache[japanesePage] = books;
          _japaneseReachedEnd = books.isEmpty ||
              !repository.hasMoreHomeBooks('和書');
          hasMoreJapanese = !_japaneseReachedEnd;
        }
      } catch (_) {
        if (japaneseBooks.isEmpty) hasMoreJapanese = false;
      } finally {
        isLoadingJapanese = false;
        notifyListeners();
      }
    }

    Future<void> loadWestern() async {
      try {
        final books = await repository.fetchBooksByGenre(
          'English',
          page: westernPage,
        );
        // A provider can silently return [] on a transient 429/5xx. Keep
        // the last successful page and its pagination cursor in that case.
        if (books.isNotEmpty || westernBooks.isEmpty) {
          westernBooks = books;
          _westernPageCache[westernPage] = books;
          _westernReachedEnd = books.isEmpty ||
              !repository.hasMoreHomeBooks('English');
          hasMoreWestern = !_westernReachedEnd;
        }
      } catch (_) {
        if (westernBooks.isEmpty) hasMoreWestern = false;
      } finally {
        isLoadingWestern = false;
        notifyListeners();
      }
    }

    Future<void> loadPopular() async {
      try {
        final books = await repository.fetchBooksByGenre(
          'ベストセラー',
          page: popularPage,
        );
        // A provider can silently return [] on a transient 429/5xx. Keep
        // the last successful page and its pagination cursor in that case.
        if (books.isNotEmpty || popularBooks.isEmpty) {
          popularBooks = books;
          _popularPageCache[popularPage] = books;
          _popularReachedEnd = books.isEmpty;
          hasMorePopular = !_popularReachedEnd;
        }
      } catch (_) {
        if (popularBooks.isEmpty) hasMorePopular = false;
      } finally {
        isLoadingPopular = false;
        notifyListeners();
      }
    }

    // Do not let a slow NDL new-arrivals query block the independent
    // language feeds or the user's timeline. Language feeds stay sequential
    // to avoid parallel requests to the low-volume public metadata service.
    Future<void> loadLanguages() async {
      await loadJapanese();
      await loadWestern();
    }

    await Future.wait<void>([
      loadRecommended(),
      loadLanguages(),
      loadPopular(),
      _loadTimeline(),
    ]);
    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadTimeline() async {
    try {
      timelinePosts = await SupabaseService().fetchTimelinePosts();
      timelineReplies = await SupabaseService().fetchRepliesForPosts(
        timelinePosts.map((post) => post.id).toList(growable: false),
      );
    } catch (_) {
      // Retain the last working timeline when its API temporarily fails.
    } finally {
      isLoadingTimeline = false;
      notifyListeners();
    }
  }

  /// Retry a transient NDL failure without reloading the timeline or popular
  /// section. The repository starts over from the preferred source.
  Future<void> retryRecommended() async {
    if (isLoadingRecommended || isLoadingMoreRecommended) return;
    isLoadingRecommended = true;
    notifyListeners();
    try {
      _repository.resetHomeBooks('新着');
      final books = await _repository.fetchBooksByGenre('新着', page: 1);
      recommendedBooks = books;
      recommendedPage = 1;
      _recommendedPageCache
        ..clear()
        ..[1] = books;
      _recommendedReachedEnd =
          books.isEmpty || !_repository.hasMoreHomeBooks('新着');
      hasMoreRecommended = !_recommendedReachedEnd;
    } catch (_) {
      hasMoreRecommended = false;
    } finally {
      isLoadingRecommended = false;
      notifyListeners();
    }
  }

  Future<void> retryJapanese() async {
    if (isLoadingJapanese || isLoadingMoreJapanese) return;
    isLoadingJapanese = true;
    notifyListeners();
    try {
      _repository.resetHomeBooks('和書');
      final books = await _repository.fetchBooksByGenre('和書', page: 1);
      japaneseBooks = books;
      japanesePage = 1;
      _japanesePageCache
        ..clear()
        ..[1] = books;
      _japaneseReachedEnd =
          books.isEmpty || !_repository.hasMoreHomeBooks('和書');
      hasMoreJapanese = !_japaneseReachedEnd;
    } catch (_) {
      hasMoreJapanese = false;
    } finally {
      isLoadingJapanese = false;
      notifyListeners();
    }
  }

  Future<void> retryWestern() async {
    if (isLoadingWestern || isLoadingMoreWestern) return;
    isLoadingWestern = true;
    notifyListeners();
    try {
      _repository.resetHomeBooks('English');
      final books = await _repository.fetchBooksByGenre('English', page: 1);
      westernBooks = books;
      westernPage = 1;
      _westernPageCache
        ..clear()
        ..[1] = books;
      _westernReachedEnd =
          books.isEmpty || !_repository.hasMoreHomeBooks('English');
      hasMoreWestern = !_westernReachedEnd;
    } catch (_) {
      hasMoreWestern = false;
    } finally {
      isLoadingWestern = false;
      notifyListeners();
    }
  }

  /// Let readers retry a transient Rakuten bestseller failure without
  /// reloading the entire Home or discarding a previously successful page.
  Future<void> retryPopular() async {
    if (isLoadingPopular || isLoadingMorePopular) return;
    isLoadingPopular = true;
    notifyListeners();
    try {
      _repository.resetHomeBooks('ベストセラー');
      final books = await _repository.fetchBooksByGenre('ベストセラー', page: 1);
      if (books.isNotEmpty || popularBooks.isEmpty) {
        popularBooks = books;
        popularPage = 1;
        _popularPageCache
          ..clear()
          ..[1] = books;
        _popularReachedEnd = books.isEmpty;
        hasMorePopular = !_popularReachedEnd;
      }
    } catch (_) {
      if (popularBooks.isEmpty) hasMorePopular = false;
    } finally {
      isLoadingPopular = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreRecommended() async {
    if (isLoadingMoreRecommended || !hasMoreRecommended) return;
    final nextPage = recommendedPage + 1;
    final cachedBooks = _recommendedPageCache[nextPage];
    if (cachedBooks != null) {
      recommendedBooks = cachedBooks;
      recommendedPage = nextPage;
      hasMoreRecommended =
          _recommendedPageCache.containsKey(nextPage + 1) ||
          !_recommendedReachedEnd;
      notifyListeners();
      return;
    }

    isLoadingMoreRecommended = true;
    notifyListeners();

    try {
      final newBooks = await _repository.fetchBooksByGenre(
        '新着',
        page: nextPage,
      );

      if (newBooks.isEmpty) {
        _recommendedReachedEnd = true;
        hasMoreRecommended = false;
      } else {
        _recommendedPageCache[nextPage] = newBooks;
        recommendedBooks = newBooks;
        recommendedPage = nextPage;
        _recommendedReachedEnd = !_repository.hasMoreHomeBooks('新着');
        hasMoreRecommended = !_recommendedReachedEnd;
      }
    } finally {
      isLoadingMoreRecommended = false;
      notifyListeners();
    }
  }

  void loadPreviousRecommended() {
    if (!canLoadPreviousRecommended || isLoadingMoreRecommended) return;
    final previousPage = recommendedPage - 1;
    final cachedBooks = _recommendedPageCache[previousPage];
    if (cachedBooks == null) return;
    recommendedBooks = cachedBooks;
    recommendedPage = previousPage;
    hasMoreRecommended = true;
    notifyListeners();
  }

  Future<void> loadMoreJapanese() async {
    if (isLoadingMoreJapanese || !hasMoreJapanese) return;
    final nextPage = japanesePage + 1;
    final cachedBooks = _japanesePageCache[nextPage];
    if (cachedBooks != null) {
      japaneseBooks = cachedBooks;
      japanesePage = nextPage;
      hasMoreJapanese =
          _japanesePageCache.containsKey(nextPage + 1) ||
          !_japaneseReachedEnd;
      notifyListeners();
      return;
    }

    isLoadingMoreJapanese = true;
    notifyListeners();

    try {
      final newBooks = await _repository.fetchBooksByGenre(
        '和書',
        page: nextPage,
      );

      if (newBooks.isEmpty) {
        _japaneseReachedEnd = true;
        hasMoreJapanese = false;
      } else {
        _japanesePageCache[nextPage] = newBooks;
        japaneseBooks = newBooks;
        japanesePage = nextPage;
        _japaneseReachedEnd = !_repository.hasMoreHomeBooks('和書');
        hasMoreJapanese = !_japaneseReachedEnd;
      }
    } finally {
      isLoadingMoreJapanese = false;
      notifyListeners();
    }
  }

  void loadPreviousJapanese() {
    if (!canLoadPreviousJapanese || isLoadingMoreJapanese) return;
    final previousPage = japanesePage - 1;
    final cachedBooks = _japanesePageCache[previousPage];
    if (cachedBooks == null) return;
    japaneseBooks = cachedBooks;
    japanesePage = previousPage;
    hasMoreJapanese = true;
    notifyListeners();
  }

  Future<void> loadMoreWestern() async {
    if (isLoadingMoreWestern || !hasMoreWestern) return;
    final nextPage = westernPage + 1;
    final cachedBooks = _westernPageCache[nextPage];
    if (cachedBooks != null) {
      westernBooks = cachedBooks;
      westernPage = nextPage;
      hasMoreWestern =
          _westernPageCache.containsKey(nextPage + 1) || !_westernReachedEnd;
      notifyListeners();
      return;
    }

    isLoadingMoreWestern = true;
    notifyListeners();

    try {
      final newBooks = await _repository.fetchBooksByGenre(
        'English',
        page: nextPage,
      );

      if (newBooks.isEmpty) {
        _westernReachedEnd = true;
        hasMoreWestern = false;
      } else {
        _westernPageCache[nextPage] = newBooks;
        westernBooks = newBooks;
        westernPage = nextPage;
        _westernReachedEnd = !_repository.hasMoreHomeBooks('English');
        hasMoreWestern = !_westernReachedEnd;
      }
    } finally {
      isLoadingMoreWestern = false;
      notifyListeners();
    }
  }

  void loadPreviousWestern() {
    if (!canLoadPreviousWestern || isLoadingMoreWestern) return;
    final previousPage = westernPage - 1;
    final cachedBooks = _westernPageCache[previousPage];
    if (cachedBooks == null) return;
    westernBooks = cachedBooks;
    westernPage = previousPage;
    hasMoreWestern = true;
    notifyListeners();
  }

  Future<void> loadMorePopular() async {
    if (isLoadingMorePopular || !hasMorePopular) return;
    final nextPage = popularPage + 1;
    final cachedBooks = _popularPageCache[nextPage];
    if (cachedBooks != null) {
      popularBooks = cachedBooks;
      popularPage = nextPage;
      hasMorePopular =
          _popularPageCache.containsKey(nextPage + 1) || !_popularReachedEnd;
      notifyListeners();
      return;
    }

    isLoadingMorePopular = true;
    notifyListeners();

    try {
      final newBooks = await _repository.fetchBooksByGenre(
        'ベストセラー',
        page: nextPage,
      );

      if (newBooks.isEmpty) {
        _popularReachedEnd = true;
        hasMorePopular = false;
      } else {
        _popularPageCache[nextPage] = newBooks;
        popularBooks = newBooks;
        popularPage = nextPage;
        _popularReachedEnd = false;
        hasMorePopular = !_popularReachedEnd;
      }
    } finally {
      isLoadingMorePopular = false;
      notifyListeners();
    }
  }

  void loadPreviousPopular() {
    if (!canLoadPreviousPopular || isLoadingMorePopular) return;
    final previousPage = popularPage - 1;
    final cachedBooks = _popularPageCache[previousPage];
    if (cachedBooks == null) return;
    popularBooks = cachedBooks;
    popularPage = previousPage;
    hasMorePopular = true;
    notifyListeners();
  }

  Future<void> loadData(BuildContext context) async => _loadData(context);

  List<Book> get books => [
    ...recommendedBooks,
    ...japaneseBooks,
    ...westernBooks,
    ...popularBooks,
  ];
}
