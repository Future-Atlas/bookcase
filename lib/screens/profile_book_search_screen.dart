import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../widgets/book_cover_image.dart';
import '../repositories/book_repository.dart';
import '../services/supabase_service.dart';
import '../widgets/post_composer_dialog.dart';
import '../widgets/book_action_label.dart';
import '../widgets/post_reply_dialog.dart';

class ProfileBookSearchScreen extends StatefulWidget {
  const ProfileBookSearchScreen({super.key, this.calendarSelection = false});

  final bool calendarSelection;

  @override
  State<ProfileBookSearchScreen> createState() =>
      _ProfileBookSearchScreenState();
}

class _ProfileBookSearchScreenState extends State<ProfileBookSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Book> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _searchUnavailable = false;
  int _nextPage = 1;
  BookRepository? _activeRepository;
  String _activeQuery = '';
  int _searchGeneration = 0;
  final Map<String, Future<bool>> _readStatusFutures = {};
  final Map<String, Future<bool>> _wantedStatusFutures = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_scheduleSearch)
      ..dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    // Invalidate any outstanding page before the next debounce fires.
    _searchGeneration++;
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _isLoadingMore = false;
        _hasMore = false;
        _searchUnavailable = false;
        _activeRepository = null;
        _activeQuery = '';
        _nextPage = 1;
        _hasSearched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _results = [];
      _isSearching = true;
      _isLoadingMore = false;
      _hasMore = false;
      _searchUnavailable = false;
      _nextPage = 1;
      _activeQuery = query;
      _hasSearched = true;
    });
    try {
      final service = Provider.of<SupabaseService>(context, listen: false);
      final allowAdultContent = await service.canViewAdultContent();
      if (!mounted || generation != _searchGeneration) return;
      final repository = BookRepository(allowAdultContent: allowAdultContent);
      _activeRepository = repository;
      final batch = await repository.searchBooksPage(query, page: 1, count: 10);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = batch.books;
        _hasMore = batch.hasMore && !batch.temporarilyUnavailable;
        _searchUnavailable = batch.temporarilyUnavailable;
        _nextPage = 2;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchUnavailable = true;
        _hasMore = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final repo = _activeRepository;
    if (repo == null || !_hasMore || _isSearching || _isLoadingMore) return;
    final generation = _searchGeneration;
    final page = _nextPage;
    setState(() => _isLoadingMore = true);
    try {
      final batch = await repo.searchBooksPage(
        _activeQuery, page: page, count: 10,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        if (batch.temporarilyUnavailable) {
          _searchUnavailable = true;
          _hasMore = false;
        } else {
          final seen = _results.map((book) => book.id).toSet();
          _results.addAll(batch.books.where((book) => seen.add(book.id)));
          _hasMore = batch.hasMore;
          _nextPage = page + 1;
        }
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchUnavailable = true;
        _hasMore = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _markAsRead(Book book) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    if (await service.isBookReadByCurrentUser(bookId: book.id)) return;
    if (!mounted) return;
    final posted = await showPostComposerDialog(context: context, book: book);
    if (!mounted || !posted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _toggleWantToRead(Book book) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    final result = await service.toggleWantToRead(book: book);
    if (!mounted) return;
    if (result == WantToReadToggleResult.subscriptionRequired) {
      await showSubscriptionLockedDialog(
        context: context,
        featureLabel: '「読みたい！」',
      );
      return;
    }
    _wantedStatusFutures[book.id] = service.isBookWantedByCurrentUser(book.id);
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Text(
          widget.calendarSelection ? 'カレンダーに追加する本を検索' : '本を検索',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'closeProfileBookSearch',
        onPressed: () => Navigator.of(context).pop(),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        tooltip: '閉じる',
        child: const Icon(Icons.close, size: 30),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  final query = value.trim();
                  if (query.isNotEmpty) _search(query);
                },
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  hintText: '本の名前・著者名を入力',
                  hintStyle: const TextStyle(color: Colors.black45),
                  prefixIcon: const Icon(Icons.search, color: Colors.black54),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.clear, color: Colors.black54),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black54),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildSearchBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBody() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
      );
    }
    if (!_hasSearched) {
      return const Center(
        child: Text('読了した本を検索してください', style: TextStyle(color: Colors.black54)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: _searchUnavailable
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('書籍の取得に失敗しました。再試行してください。'),
                  TextButton(
                    onPressed: () => _search(_searchController.text.trim()),
                    child: const Text('再試行'),
                  ),
                ],
              )
            : _hasMore
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '最初の候補に表示可能な書籍がありません。続きを検索できます。',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: _loadMore,
                        child: const Text('次の10件を探す'),
                      ),
                    ],
                  )
                : const Text(
                    '該当する本が見つかりませんでした',
                    style: TextStyle(color: Colors.black54),
                  ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _results.length + (_hasMore || _isLoadingMore || _searchUnavailable ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _results.length) {
          if (_isLoadingMore) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: OutlinedButton.icon(
              onPressed: _searchUnavailable
                  ? () => _search(_searchController.text.trim())
                  : _loadMore,
              icon: Icon(_searchUnavailable ? Icons.refresh : Icons.expand_more),
              label: Text(_searchUnavailable ? '再試行' : 'さらに10件読み込む'),
            ),
          );
        }
        final book = _results[index];
        return Material(
          color: const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 72,
                  height: 104,
                  color: Colors.grey[300],
                  child: BookCoverImage(book: book),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        book.author.isEmpty ? '著者不明' : book.author,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.calendarSelection)
                            FilledButton.icon(
                              onPressed: () => Navigator.of(context).pop(book),
                              icon: const Icon(Icons.timer_outlined),
                              label: const Text('この本で計測'),
                            ),
                          if (!widget.calendarSelection)
                            FutureBuilder<bool>(
                              future: _readStatusFutures.putIfAbsent(
                              book.id,
                              () => Provider.of<SupabaseService>(
                                context,
                                listen: false,
                              ).isBookReadByCurrentUser(bookId: book.id),
                            ),
                            builder: (context, snapshot) {
                              final isRead = snapshot.data ?? false;
                              final isChecking =
                                  snapshot.connectionState ==
                                  ConnectionState.waiting;
                              return ElevatedButton(
                                onPressed: isRead || isChecking
                                    ? null
                                    : () => _markAsRead(book),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: const Color(0xFFFF1F1F),
                                  disabledBackgroundColor: Colors.black,
                                  disabledForegroundColor: isRead
                                      ? const Color(0xFF00BFFF)
                                      : Colors.grey,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: BookActionLabel(
                                  bookId: book.id,
                                  label: isRead ? '読了済み' : '読了',
                                  color: isRead
                                      ? const Color(0xFF00BFFF)
                                      : const Color(0xFFFF1F1F),
                                  wantToRead: false,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                          if (!widget.calendarSelection)
                            const SizedBox(width: 8),
                          if (!widget.calendarSelection)
                            FutureBuilder<bool>(
                              future: _wantedStatusFutures.putIfAbsent(
                              book.id,
                              () => Provider.of<SupabaseService>(
                                context,
                                listen: false,
                              ).isBookWantedByCurrentUser(book.id),
                            ),
                            builder: (context, snapshot) {
                              final wanted = snapshot.data ?? false;
                              return ElevatedButton(
                                onPressed:
                                    snapshot.connectionState ==
                                        ConnectionState.waiting
                                    ? null
                                    : () => _toggleWantToRead(book),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.amber,
                                  disabledBackgroundColor: Colors.black,
                                  disabledForegroundColor:
                                      Colors.amber.shade200,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: BookActionLabel(
                                  bookId: book.id,
                                  label: wanted ? '読みたい！済み' : '読みたい！',
                                  color: Colors.amber,
                                  wantToRead: true,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
