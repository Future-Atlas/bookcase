import 'dart:async';

import 'package:flutter/material.dart';
import '../models/book.dart';
import '../api/ndl_api.dart';
import '../api/openbd_api.dart';
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
  bool isLoadingWestern = true;
  bool isLoadingPopular = true;
  bool isLoadingTimeline = true;

  bool isSearching = false;
  bool hasMoreSearch = true;
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

  void initialize(BuildContext context, {bool timelineOnly = false}) {
    _timelineOnly = timelineOnly;
    _loadData(context);
    searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _featuredLookupGeneration++;
    searchController.removeListener(_onSearchChanged);
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    searchQuery = searchController.text.trim();
    _searchDebounce?.cancel();

    if (searchQuery.isEmpty) {
      isSearching = false;
      hasMoreSearch = true;
      searchPage = 1;
      searchResults = [];
      userSearchResults = [];
      _searchResultIds.clear();
      notifyListeners();
      return;
    }

    isSearching = true;
    notifyListeners();

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (userSearchMode) {
        _searchUsers();
      } else {
        _searchBooks(reset: true);
      }
    });
  }

  void setUserSearchMode(bool enabled) {
    if (userSearchMode == enabled) return;
    userSearchMode = enabled;
    _searchDebounce?.cancel();
    isSearching = false;
    hasMoreSearch = true;
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
    final query = searchQuery.trim();
    if (query.isEmpty || userSearchMode) {
      isSearching = false;
      notifyListeners();
      return;
    }

    if (reset) {
      hasMoreSearch = true;
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
        count: 20,
      );

      // 入力中に別の検索が始まった場合は、古い結果を画面へ反映しない。
      if (userSearchMode || query != searchQuery.trim()) return;

      for (final book in batch.books) {
        if (_searchResultIds.add(book.id)) {
          searchResults.add(book);
        }
      }

      searchPage = requestedPage + 1;
      hasMoreSearch = batch.hasMore;
    } finally {
      if (!userSearchMode && query == searchQuery.trim()) {
        isSearching = false;
        notifyListeners();
      }
    }
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
        final found = await NdlApi.fetchBookById(normalizedId);
        final enhanced = found == null
            ? const <Book>[]
            : await OpenBdApi.enrich(<Book>[found]);
        fresh = enhanced.isEmpty ? null : enhanced.first;
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
        coverUrl: fresh.coverUrl,
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
    isLoadingWestern = true;
    isLoadingPopular = true;
    isLoadingFeatured = true;
    isLoadingTimeline = true;
    notifyListeners();

    _allowAdultContent = await SupabaseService().canViewAdultContent();
    _catalogRepository = BookRepository(allowAdultContent: _allowAdultContent);
    final repository = _repository;

    recommendedPage = 1;
    westernPage = 1;
    popularPage = 1;
    hasMoreRecommended = true;
    hasMoreWestern = true;
    hasMorePopular = true;
    _recommendedPageCache.clear();
    _westernPageCache.clear();
    _popularPageCache.clear();
    _recommendedReachedEnd = false;
    _westernReachedEnd = false;
    _popularReachedEnd = false;
    recommendedBooks = [];
    westernBooks = [];
    popularBooks = [];
    featuredBooks = [];
    final featuredGeneration = ++_featuredLookupGeneration;
    timelinePosts = [];
    timelineReplies = {};
    notifyListeners();

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
      featuredBooks = [];
    } finally {
      isLoadingFeatured = false;
      notifyListeners();
    }
    if (featuredBooks.isNotEmpty) {
      unawaited(_hydrateFeaturedBooks(featuredGeneration));
    }

    try {
      recommendedBooks = await repository.fetchBooksByGenre(
        '新着',
        page: recommendedPage,
      );
      _recommendedPageCache[recommendedPage] = recommendedBooks;
      _recommendedReachedEnd = recommendedBooks.isEmpty ||
          !repository.hasMoreHomeBooks('新着');
      hasMoreRecommended = !_recommendedReachedEnd;
    } catch (_) {
      recommendedBooks = [];
      hasMoreRecommended = false;
    } finally {
      isLoadingRecommended = false;
      notifyListeners();
    }

    try {
      westernBooks = await repository.fetchBooksByGenre(
        'English',
        page: westernPage,
      );
      _westernPageCache[westernPage] = westernBooks;
      _westernReachedEnd = westernBooks.isEmpty ||
          !repository.hasMoreHomeBooks('English');
      hasMoreWestern = !_westernReachedEnd;
    } catch (_) {
      westernBooks = [];
      hasMoreWestern = false;
    } finally {
      isLoadingWestern = false;
      notifyListeners();
    }

    try {
      popularBooks = await repository.fetchBooksByGenre(
        'ベストセラー',
        page: popularPage,
      );
      _popularPageCache[popularPage] = popularBooks;
      _popularReachedEnd = popularBooks.isEmpty;
      hasMorePopular = !_popularReachedEnd;
    } catch (_) {
      popularBooks = [];
      hasMorePopular = false;
    } finally {
      isLoadingPopular = false;
      notifyListeners();
    }

    await _loadTimeline();
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
      timelinePosts = [];
      timelineReplies = {};
    } finally {
      isLoadingTimeline = false;
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
    ...westernBooks,
    ...popularBooks,
  ];
}
