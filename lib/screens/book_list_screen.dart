import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../widgets/book_card.dart';
import '../config/feature_flags.dart';
import '../widgets/book_search_results.dart';
import '../widgets/catalog_credit.dart';
import '../models/profile_page_color.dart';
import '../api/ndl_api.dart';
import '../api/openbd_api.dart';
import '../widgets/post_card.dart';
import '../widgets/timeline_ad_slot.dart';
import '../widgets/timeline_ad_policy.dart';
import '../controllers/book_list_controller.dart';
import '../models/book.dart';
import '../models/post.dart';
import '../models/post_reply.dart';
import '../models/social_models.dart';
import '../services/content_safety_service.dart';
import '../services/supabase_service.dart';
import '../widgets/post_composer_dialog.dart';
import '../widgets/post_reply_dialog.dart';
import '../widgets/favorite_replacement_dialog.dart';
import '../widgets/book_action_label.dart';
import '../widgets/rakuten_book_link.dart';
import '../widgets/public_posts_link.dart';
import '../utils/book_carousel_auto_advance.dart';
import 'report_post_dialog.dart';
import 'user_profile_screen.dart';
import 'post_engagement_users_screen.dart';

class BookListScreen extends StatefulWidget {
  const BookListScreen({
    super.key,
    this.onOpenUserProfile,
    this.initialGenre,
    this.initialBookId,
    this.timelineOnly = false,
  });

  final ValueChanged<String>? onOpenUserProfile;
  final String? initialGenre;
  final String? initialBookId;
  final bool timelineOnly;

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  late final BookListController _controller;
  final ScrollController _timelineScrollController = ScrollController();
  final Set<String> _pendingReactionPostIds = <String>{};
  final GlobalKey<_PagedBookScrollerState> _featuredScrollerKey = GlobalKey();
  final GlobalKey<_PagedBookScrollerState> _popularScrollerKey = GlobalKey();
  final GlobalKey<_PagedBookScrollerState> _newArrivalsScrollerKey =
      GlobalKey();
  final GlobalKey<_PagedBookScrollerState> _westernScrollerKey = GlobalKey();
  String? _openingBookId;
  bool _isServiceIntroductionExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = BookListController();
    _controller.initialize(context, timelineOnly: widget.timelineOnly);
    if (widget.initialBookId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialBook());
    }
  }

  Future<void> _openInitialBook() async {
    final initialBookId = widget.initialBookId?.trim() ?? '';
    if (initialBookId.isEmpty || _openingBookId == initialBookId) return;
    _openingBookId = initialBookId;
    final found = await NdlApi.fetchBookById(initialBookId);
    final enriched = await OpenBdApi.enrich(
      found == null ? <Book>[] : <Book>[found],
    );
    final book = enriched.isEmpty ? null : enriched.first;
    if (!mounted) return;
    if (book != null) {
      await _showBookDetailDialog(book, openedFromDirectUrl: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('書籍情報を取得できませんでした。時間をおいて再度お試しください。')),
      );
    }
    _openingBookId = null;
  }

  @override
  void didUpdateWidget(covariant BookListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBookId != oldWidget.initialBookId &&
        widget.initialBookId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialBook());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _timelineScrollController.dispose();
    super.dispose();
  }

  Future<void> _showPostComposerDialog(Book book) async {
    final posted = await showPostComposerDialog(context: context, book: book);
    if (posted && mounted) {
      _controller.loadData(context);
    }
  }

  Future<void> _editPost(Post post) async {
    final book = Book(
      id: post.bookId,
      title: post.bookTitle,
      author: post.bookAuthor,
      publisher: '',
      pubDate: '',
      isbn: post.bookId,
      coverUrl: post.bookCoverUrl,
    );
    final edited = await showPostComposerDialog(
      context: context,
      book: book,
      existingPost: post,
    );
    if (edited && mounted) await _controller.loadData(context);
  }

  Future<void> _openBookFromPost(Post post) async {
    final resolvedBook = await NdlApi.fetchBookById(post.bookId);
    if (!mounted) return;
    final book =
        resolvedBook ??
        Book(
          id: post.bookId,
          title: post.bookTitle,
          author: post.bookAuthor,
          publisher: '',
          pubDate: '',
          isbn: post.bookId,
          coverUrl: post.bookCoverUrl,
        );
    await _showBookDetailDialog(book);
  }

  Future<bool> _ensureAuthenticated() async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    if (service.canWrite) return true;
    final result = await Navigator.of(context).pushNamed('/login');
    return mounted && (result == true || service.canWrite);
  }

  Future<void> _openUserProfile(String profileId) async {
    final openInMainShell = widget.onOpenUserProfile;
    if (openInMainShell != null) {
      openInMainShell(profileId);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          profileId: profileId,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) await _controller.loadData(context);
  }

  Future<void> _setUserSearchMode(bool enabled) async {
    if (enabled && !await _ensureAuthenticated()) return;
    if (!mounted) return;
    _controller.setUserSearchMode(enabled);
  }

  Future<void> _toggleReaction(String postId, PostReactionType reaction) async {
    if (!await _ensureAuthenticated() || !mounted) return;
    if (!_pendingReactionPostIds.add(postId)) return;

    final previous = _controller.toggleTimelineReactionOptimistically(
      postId,
      reaction,
    );
    final service = Provider.of<SupabaseService>(context, listen: false);
    final success = await service.setPostReaction(postId, reaction);
    _pendingReactionPostIds.remove(postId);
    if (!mounted) return;

    if (!success && previous != null) {
      _controller.restoreTimelinePost(previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('リアクションを更新できませんでした。')));
    }
  }

  Future<void> _toggleWantToReadFromPost(Post post) async {
    if (!await _ensureAuthenticated() || !mounted) return;
    if (!_pendingReactionPostIds.add('want:${post.id}')) return;
    final previous = _controller.toggleTimelineWantToReadOptimistically(
      post.id,
    );
    final service = Provider.of<SupabaseService>(context, listen: false);
    final result = await service.toggleWantToRead(
      book: Book(
        id: post.bookId,
        title: post.bookTitle,
        author: post.bookAuthor,
        publisher: '',
        pubDate: '',
        isbn: post.bookId,
        coverUrl: post.bookCoverUrl,
      ),
      sourcePostId: post.id,
    );
    _pendingReactionPostIds.remove('want:${post.id}');
    if (!mounted) return;
    if (result == WantToReadToggleResult.subscriptionRequired) {
      if (previous != null) _controller.restoreTimelinePost(previous);
      await showSubscriptionLockedDialog(
        context: context,
        featureLabel: '「読みたい！」',
      );
      return;
    }
    if (result.shouldRestoreOptimisticState && previous != null) {
      _controller.restoreTimelinePost(previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _openEngagementUsers(
    Post post, {
    PostReactionType? reaction,
    bool wantToRead = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => PostEngagementUsersScreen(
          postId: post.id,
          title: wantToRead ? '「読みたい！」したユーザー' : '${reaction!.symbol}したユーザー',
          reaction: reaction,
          wantToRead: wantToRead,
          onProfileTap: (profile) {
            Navigator.of(routeContext).pop();
            _openUserProfile(profile.id);
          },
        ),
      ),
    );
  }

  Future<void> _reportPost(String postId) async {
    if (!await _ensureAuthenticated() || !mounted) return;
    await showPostReportDialog(context: context, postId: postId);
  }

  Future<void> _reportReply(PostReply reply) async {
    if (!await _ensureAuthenticated() || !mounted) return;
    final service = Provider.of<SupabaseService>(context, listen: false);
    if (reply.profileId == service.activeProfileId) return;
    await showReplyReportDialog(context: context, replyId: reply.id);
  }

  Future<void> _replyToPost(Post post, [PostReply? parentReply]) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    final canReply = await service.canCreatePostReplies();
    if (!mounted) return;
    if (!canReply) {
      await showPostReplyLockedDialog(context: context);
      return;
    }
    final posted = await showPostReplyDialog(
      context: context,
      postId: post.id,
      parentReplyId: parentReply?.id,
      replyToUsername: parentReply?.username,
    );
    if (posted && mounted) {
      await _controller.loadData(context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('返信を投稿しました。')));
    }
  }

  void _showFavoriteResult(FavoriteToggleResult result) {
    final message = switch (result) {
      FavoriteToggleResult.added => 'お気に入りに登録しました。',
      FavoriteToggleResult.removed => 'お気に入りから解除しました。',
      FavoriteToggleResult.standardLimitReached =>
        'お気に入りは3冊までです。登録済みの本と入れ替えてください。',
      FavoriteToggleResult.subscriberLimitReached =>
        'お気に入りは12冊までです。登録済みの本と入れ替えてください。',
      FavoriteToggleResult.requiresRead => '読了（投稿）した本のみお気に入りに追加できます。',
      FavoriteToggleResult.failed => 'お気に入りを更新できませんでした。',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _replaceFavoriteAtLimit({
    required String targetBookId,
    required String targetBookTitle,
  }) async {
    final replaced = await showFavoriteReplacementDialog(
      context: context,
      targetBookId: targetBookId,
      targetBookTitle: targetBookTitle,
    );
    if (!mounted || !replaced) return false;
    await _controller.loadData(context);
    if (!mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('お気に入りを入れ替えました。')));
    return true;
  }

  Future<void> _toggleFavoriteFromPost(Post post) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    final result = await service.toggleFavorite(post.bookId);
    if (!mounted) return;
    if (result == FavoriteToggleResult.standardLimitReached ||
        result == FavoriteToggleResult.subscriberLimitReached) {
      await _replaceFavoriteAtLimit(
        targetBookId: post.bookId,
        targetBookTitle: post.bookTitle,
      );
      return;
    }
    _showFavoriteResult(result);
  }

  Future<void> _deletePost(Post post) async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    // Temporarily disable ownership auth check for public browsing mode.
    // if (post.profileId != service.activeProfileId) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('投稿を削除しますか？'),
        content: Text(
          '「${post.bookTitle}」の投稿を削除します。\n'
          'この本への投稿がほかにない場合、My 本棚からも削除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await service.deleteOwnPost(post.id);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('投稿を削除できませんでした。')));
      return;
    }
    await _controller.loadData(context);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('投稿を削除しました。')));
  }

  String _currentAppPath() {
    final fragment = Uri.base.fragment;
    if (fragment.startsWith('/')) return Uri.parse(fragment).path;
    return Uri.base.path.isEmpty ? '/' : Uri.base.path;
  }

  void _replaceBrowserPath(String path) {
    if (!kIsWeb) return;
    SystemNavigator.routeInformationUpdated(
      uri: Uri(path: path),
      replace: true,
    );
  }

  Future<void> _showBookDetailDialog(
    Book book, {
    bool openedFromDirectUrl = false,
  }) async {
    if (ContentSafetyService.isAdultBook(book)) {
      final service = Provider.of<SupabaseService>(context, listen: false);
      final canView = await service.canViewAdultContent();
      if (!mounted) return;
      if (!canView) {
        if (openedFromDirectUrl) _replaceBrowserPath('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('この書籍は18歳未満の利用者には表示できません。')),
        );
        return;
      }
    }
    if (_openingBookId != null && !openedFromDirectUrl) return;
    final previousPath = _currentAppPath();
    final canonicalBookId = (book.isbn.isNotEmpty ? book.isbn : book.id).trim();
    final bookPath = '/book/${Uri.encodeComponent(canonicalBookId)}';
    if (canonicalBookId.isNotEmpty && previousPath != bookPath) {
      _replaceBrowserPath(bookPath);
    }

    try {
      await showDialog(
        context: context,
        builder: (context) {
          final hasCover = book.coverUrl.trim().isNotEmpty;
          final service = Provider.of<SupabaseService>(context, listen: false);
          final isReadFuture = service.isBookReadByCurrentUser(bookId: book.id);
          final isFavoriteFuture = FeatureFlags.favoritesUiEnabled
              ? service.isBookFavoritedByCurrentUser(book.id)
              : null;
          final isWantedFuture = FeatureFlags.wantToReadUiEnabled
              ? service.isBookWantedByCurrentUser(book.id)
              : Future<bool>.value(false);

          return Dialog(
            backgroundColor: const Color(0xFFE6E6E6),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 920,
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: Color(0xFF1E1E1E)),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 560;

                        final coverBlock = SizedBox(
                          width: isNarrow ? double.infinity : 220,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: isNarrow ? double.infinity : 200,
                                height: isNarrow ? 240 : 300,
                                color: Colors.grey[400],
                                child: hasCover
                                    ? Image.network(
                                        book.coverUrl,
                                        fit: BoxFit.cover,
                                        alignment: isNarrow
                                            ? Alignment.topCenter
                                            : Alignment.center,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return _buildMissingCoverFallback(
                                                book,
                                              );
                                            },
                                      )
                                    : _buildMissingCoverFallback(book),
                              ),
                              const SizedBox(height: 12),
                              if (!hasCover) ...[
                                Text(
                                  book.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E1E1E),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  book.author,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );

                        final detailBlock = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FutureBuilder<bool>(
                              future: isReadFuture,
                              builder: (context, snapshot) {
                                final isRead = snapshot.data ?? false;
                                final isChecking =
                                    snapshot.connectionState ==
                                    ConnectionState.waiting;
                                return Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 64,
                                        child: ElevatedButton(
                                          onPressed: isRead || isChecking
                                              ? null
                                              : () async {
                                                  if (!mounted) return;
                                                  Navigator.of(
                                                    this.context,
                                                  ).pop();
                                                  _showPostComposerDialog(book);
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.black,
                                            foregroundColor: const Color(
                                              0xFFFF1F1F,
                                            ),
                                            disabledBackgroundColor:
                                                Colors.black,
                                            disabledForegroundColor: isRead
                                                ? const Color(0xFF00BFFF)
                                                : Colors.grey,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
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
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    if (FeatureFlags.wantToReadUiEnabled)
                                      Expanded(
                                        child: FutureBuilder<bool>(
                                          future: isWantedFuture,
                                          builder: (context, wantedSnapshot) {
                                            final wanted =
                                                wantedSnapshot.data ?? false;
                                            final checking =
                                                wantedSnapshot
                                                    .connectionState ==
                                                ConnectionState.waiting;
                                            return SizedBox(
                                              height: 64,
                                              child: ElevatedButton(
                                                onPressed: checking
                                                    ? null
                                                    : () async {
                                                        if (!await _ensureAuthenticated() ||
                                                            !mounted) {
                                                          return;
                                                        }
                                                        final result =
                                                            await service
                                                                .toggleWantToRead(
                                                                  book: book,
                                                                );
                                                        if (!mounted) return;
                                                        if (result ==
                                                            WantToReadToggleResult
                                                                .subscriptionRequired) {
                                                          await showSubscriptionLockedDialog(
                                                            context:
                                                                this.context,
                                                            featureLabel:
                                                                '「読みたい！」',
                                                          );
                                                          return;
                                                        }
                                                        if (context.mounted &&
                                                            !result
                                                                .shouldRestoreOptimisticState) {
                                                          Navigator.of(
                                                            context,
                                                          ).pop();
                                                        }
                                                        ScaffoldMessenger.of(
                                                          this.context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              result.message,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.black,
                                                  foregroundColor: Colors.amber,
                                                  disabledBackgroundColor:
                                                      Colors.black,
                                                  disabledForegroundColor:
                                                      Colors.amber.shade200,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                  ),
                                                ),
                                                child: BookActionLabel(
                                                  bookId: book.id,
                                                  label: wanted
                                                      ? '読みたい！済み'
                                                      : '読みたい！',
                                                  color: Colors.amber,
                                                  wantToRead: true,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            if (FeatureFlags.favoritesUiEnabled)
                              FutureBuilder<bool>(
                                future: isFavoriteFuture,
                                builder: (context, snapshot) {
                                  final isFavorite = snapshot.data ?? false;
                                  final isLoading =
                                      snapshot.connectionState ==
                                      ConnectionState.waiting;
                                  return Align(
                                    alignment: Alignment.center,
                                    child: OutlinedButton.icon(
                                      onPressed: isLoading
                                          ? null
                                          : () async {
                                              // Temporarily disable auth check for
                                              // public browsing mode.
                                              // if (!service.isAuthenticated) {
                                              //   Navigator.of(context).pop();
                                              //   final authenticated =
                                              //       await _ensureAuthenticated();
                                              //   if (authenticated && mounted) {
                                              //     _showBookDetailDialog(book);
                                              //   }
                                              //   return;
                                              // }

                                              final result = await service
                                                  .toggleFavorite(book.id);
                                              if (!mounted) return;
                                              if (result ==
                                                  FavoriteToggleResult
                                                      .standardLimitReached) {
                                                final replaced =
                                                    await _replaceFavoriteAtLimit(
                                                      targetBookId: book.id,
                                                      targetBookTitle:
                                                          book.title,
                                                    );
                                                if (replaced &&
                                                    context.mounted) {
                                                  Navigator.of(context).pop();
                                                }
                                                return;
                                              }
                                              if (context.mounted &&
                                                  (result ==
                                                          FavoriteToggleResult
                                                              .added ||
                                                      result ==
                                                          FavoriteToggleResult
                                                              .removed)) {
                                                Navigator.of(context).pop();
                                              }
                                              _showFavoriteResult(result);
                                            },
                                      icon: Icon(
                                        isFavorite
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: const Color(0xFFD00303),
                                      ),
                                      label: Text(
                                        isFavorite ? 'お気に入り解除' : 'お気に入りに登録',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            Row(
                              children: [
                                ...List.generate(5, (index) {
                                  final isFilled =
                                      index < book.ratingAvg.floor();
                                  return Icon(
                                    isFilled ? Icons.star : Icons.star_border,
                                    color: const Color(0xFFE0B400),
                                    size: isNarrow ? 30 : 42,
                                  );
                                }),
                                SizedBox(width: isNarrow ? 8 : 12),
                                Text(
                                  book.ratingAvg.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: Color(0xFFE0B400),
                                    fontSize: isNarrow ? 20 : 52 / 2,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              book.title.trim().isEmpty ? 'タイトル不明' : book.title,
                              style: const TextStyle(
                                color: Color(0xFF1E1E1E),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              book.author.trim().isEmpty ? '著者不明' : book.author,
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              book.publisher.trim().isEmpty
                                  ? '出版社不明'
                                  : book.publisher,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              color: const Color(0xFFD8D8D8),
                              child: SizedBox(
                                height: isNarrow ? 170 : 230,
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    child: Text(
                                      book.description.trim().isNotEmpty
                                          ? book.description
                                          : 'あらすじ情報はまだ登録されていません。',
                                      style: const TextStyle(
                                        color: Color(0xFF1E1E1E),
                                        fontSize: 26 / 2,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );

                        final bookInformation = isNarrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  coverBlock,
                                  const SizedBox(height: 12),
                                  detailBlock,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  coverBlock,
                                  const SizedBox(width: 20),
                                  Expanded(child: detailBlock),
                                ],
                              );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            bookInformation,
                            RakutenBookLink(book: book),
                            const SizedBox(height: 20),
                            _BookPostsPanel(
                              bookId: book.id,
                              onUserTap: _openUserProfile,
                              onReaction: (post, reaction) =>
                                  _toggleReaction(post.id, reaction),
                              onReport: (post) => _reportPost(post.id),
                              onReply: _replyToPost,
                              onReplyReport: _reportReply,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted && kIsWeb && _currentAppPath() == bookPath) {
        _replaceBrowserPath(
          openedFromDirectUrl || previousPath.startsWith('/book/')
              ? '/'
              : previousPath,
        );
      }
    }
  }

  Widget _buildMissingCoverFallback(Book book) {
    return Container(
      color: Colors.grey[300],
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.menu_book, size: 28, color: Colors.black54),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            book.author,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (widget.timelineOnly) {
          return LayoutBuilder(
            builder: (context, constraints) => RefreshIndicator(
              onRefresh: () => _controller.loadData(context),
              child: _buildTimeline(
                height: constraints.maxHeight,
                embedded: false,
              ),
            ),
          );
        }
        return Container(
          width: double.infinity,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: RefreshIndicator(
            onRefresh: () => _controller.loadData(context),
            color: const Color(0xFFD00303),
            child: Listener(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopHeroImage(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSearchBar(),
                          if (widget.initialGenre == null &&
                              _controller.searchQuery.isEmpty)
                            _buildServiceIntroduction(),
                          if (_controller.searchQuery.isNotEmpty)
                            _buildSearchResults()
                          else ...[
                            if ((widget.initialGenre == null &&
                                    (_controller.isLoadingFeatured ||
                                        _controller
                                            .featuredBooks
                                            .isNotEmpty)) ||
                                widget.initialGenre == 'featured')
                              _buildFeaturedBooksSection(),
                            if (widget.initialGenre == null ||
                                widget.initialGenre == 'popular')
                              _buildGenreSection(
                                title: '人気作品',
                                scrollerKey: _popularScrollerKey,
                                bookList: _controller.popularBooks,
                                pageNumber: _controller.popularPage,
                                onLoadMore: _controller.loadMorePopular,
                                onLoadPrevious: _controller.loadPreviousPopular,
                                canLoadPrevious:
                                    _controller.canLoadPreviousPopular,
                                isLoadingMore: _controller.isLoadingMorePopular,
                                hasMore: _controller.hasMorePopular,
                                isLoadingInitial: _controller.isLoadingPopular,
                              ),
                            // Only place the genre ad between real book rows.
                            if (kIsWeb &&
                                timelineAdDisplayReady &&
                                widget.initialGenre == null &&
                                _controller.popularBooks.isNotEmpty &&
                                _controller.recommendedBooks.isNotEmpty)
                              const TimelineAdSlot(
                                key: ValueKey('home-ad-between-popular-new'),
                                slotIndex: 0,
                              ),
                            if (widget.initialGenre == null ||
                                widget.initialGenre == 'recommended')
                              _buildGenreSection(
                                title: '新着',
                                scrollerKey: _newArrivalsScrollerKey,
                                bookList: _controller.recommendedBooks,
                                pageNumber: _controller.recommendedPage,
                                onLoadMore: _controller.loadMoreRecommended,
                                onLoadPrevious:
                                    _controller.loadPreviousRecommended,
                                canLoadPrevious:
                                    _controller.canLoadPreviousRecommended,
                                isLoadingMore:
                                    _controller.isLoadingMoreRecommended,
                                hasMore: _controller.hasMoreRecommended,
                                isLoadingInitial:
                                    _controller.isLoadingRecommended,
                                onRetry: () => unawaited(
                                  _controller.retryRecommended(),
                                ),
                              ),
                            if (kIsWeb &&
                                timelineAdDisplayReady &&
                                widget.initialGenre == null &&
                                _controller.recommendedBooks.isNotEmpty &&
                                _controller.westernBooks.isNotEmpty)
                              const TimelineAdSlot(
                                key: ValueKey('home-ad-between-new-western'),
                                slotIndex: 1,
                              ),
                            if (widget.initialGenre == null ||
                                widget.initialGenre == 'western')
                              _buildGenreSection(
                                title: '洋書',
                                scrollerKey: _westernScrollerKey,
                                bookList: _controller.westernBooks,
                                pageNumber: _controller.westernPage,
                                onLoadMore: _controller.loadMoreWestern,
                                onLoadPrevious: _controller.loadPreviousWestern,
                                canLoadPrevious:
                                    _controller.canLoadPreviousWestern,
                                isLoadingMore: _controller.isLoadingMoreWestern,
                                hasMore: _controller.hasMoreWestern,
                                isLoadingInitial: _controller.isLoadingWestern,
                                onRetry: () => unawaited(
                                  _controller.retryWestern(),
                                ),
                              ),
                            if (widget.initialGenre == null) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: PublicPostsLink(
                                  sectionHeading: true,
                                  foregroundColor: ProfilePageColors.colorFor(
                                    context
                                        .watch<SupabaseService>()
                                        .activePageColorKey,
                                  ),
                                ),
                              ),
                              _buildTimeline(),
                            ],
                          ],
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHeroImage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        height: 140.5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF090909)),
            ClipPath(
              clipper: _DiagonalRedClipper(),
              child: const ColoredBox(color: Color.fromARGB(255, 208, 3, 3)),
            ),
            Image.asset(
              'assets/images/Sharemarium.png',
              fit: BoxFit.fill,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    'Sharemarium',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 96,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF009D5B), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 42,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'ユーザー検索',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Switch(
                  value: _controller.userSearchMode,
                  onChanged: _setUserSearchMode,
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TextField(
              controller: _controller.searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _controller.userSearchMode
                    ? 'ユーザー名・ユーザーIDで検索'
                    : '本を検索（作品名、著者、出版社）',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(
                  _controller.userSearchMode
                      ? Icons.person_search
                      : Icons.search,
                  color: const Color(0xFFD00303),
                ),
                suffixIcon: _controller.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _controller.searchController.clear,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceIntroduction() {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color;
    final mutedColor = textColor?.withValues(alpha: 0.72);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: const Color(0xFFD00303).withValues(alpha: 0.28),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Sharemariumでできること',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                key: const ValueKey('service-introduction-toggle'),
                tooltip: _isServiceIntroductionExpanded ? '閉じる' : '開く',
                onPressed: () {
                  setState(() {
                    _isServiceIntroductionExpanded =
                        !_isServiceIntroductionExpanded;
                  });
                },
                icon: Icon(
                  _isServiceIntroductionExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
              ),
            ],
          ),
          if (_isServiceIntroductionExpanded) ...[
            const SizedBox(height: 10),
            Text(
              'Sharemariumは、読んだ本の感想を自分の言葉で記録し、ほかの読者のレビューから新しい本や視点に出会うための読書レビューSNSです。',
              style: TextStyle(color: textColor, height: 1.65),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildServicePoint(
                  icon: Icons.rate_review_outlined,
                  title: '読書体験をレビューとして残す',
                  description:
                      '読んだ本を評価するだけでなく、印象に残った点や読後の考えを文章で記録できます。読んだ本を記録して、あなただけの本棚を作りましょう！',
                ),
                _buildServicePoint(
                  icon: Icons.people_outline,
                  title: '他の読者の感想に触れる',
                  description:
                      '他ユーザーのレビューやリアクションを通じて、同じ作品を読んだ人の、自分と異なる感想に触れることができます。',
                ),
                _buildServicePoint(
                  icon: Icons.menu_book_outlined,
                  title: '次に読む本を見つける',
                  description:
                      '「タイトル・著者・出版社」で検索することができます。気になる書籍のレビューを読んで、次に読む本を決めましょう！',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PublicPostsLink(
                  foregroundColor: ProfilePageColors.colorFor(
                    context.watch<SupabaseService>().activePageColorKey,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/about'),
                  child: const Text('サービス・運営方針について'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'あなたの感想や交流が、Sharemariumを作ります。',
              style: TextStyle(color: mutedColor, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServicePoint({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFFD00303)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.78),
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenreSection({
    required String title,
    required GlobalKey<_PagedBookScrollerState> scrollerKey,
    required List<Book> bookList,
    required int pageNumber,
    required Future<void> Function() onLoadMore,
    required VoidCallback onLoadPrevious,
    required bool canLoadPrevious,
    required bool isLoadingMore,
    required bool hasMore,
    required bool isLoadingInitial,
    VoidCallback? onRetry,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title,
          failedToLoad: bookList.isEmpty && !isLoadingInitial,
        ),
        _buildBookCarousel(
          bookList,
          scrollerKey: scrollerKey,
          pageNumber: pageNumber,
          isLoadingInitial: isLoadingInitial,
          onLoadMore: onLoadMore,
          onLoadPrevious: onLoadPrevious,
          canLoadPrevious: canLoadPrevious,
          isLoadingMore: isLoadingMore,
          hasMore: hasMore,
          onRetry: onRetry,
        ),
      ],
    );
  }

  Widget _buildFeaturedBooksSection() {
    final dedicatedPage = widget.initialGenre == 'featured';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: dedicatedPage
              ? const Text(
                  '注目の書籍',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                )
              : TextButton.icon(
                  key: const ValueKey('featured-books-link'),
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/featured-books'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('注目の書籍'),
                  style: TextButton.styleFrom(
                    foregroundColor: ProfilePageColors.colorFor(
                      context.watch<SupabaseService>().activePageColorKey,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ),
        if (_controller.featuredBooks.isEmpty && !_controller.isLoadingFeatured)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '現在、公開中の注目書籍はありません。',
              textAlign: TextAlign.center,
            ),
          )
        else
          _buildBookCarousel(
            _controller.featuredBooks,
            scrollerKey: _featuredScrollerKey,
            pageNumber: 1,
            isLoadingInitial: _controller.isLoadingFeatured,
            onLoadMore: () async {},
            onLoadPrevious: () {},
            canLoadPrevious: false,
            isLoadingMore: false,
            hasMore: false,
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {bool failedToLoad = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
          ),
          if (failedToLoad) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFD00303).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '取得できませんでした',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFFD00303),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookCarousel(
    List<Book> bookList, {
    required GlobalKey<_PagedBookScrollerState> scrollerKey,
    required int pageNumber,
    required bool isLoadingInitial,
    required Future<void> Function() onLoadMore,
    required VoidCallback onLoadPrevious,
    required bool canLoadPrevious,
    required bool isLoadingMore,
    required bool hasMore,
    VoidCallback? onRetry,
  }) {
    if (bookList.isEmpty) {
      if (isLoadingInitial) {
        return Container(
          height: 220,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFD00303).withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ProfilePageColors.colorFor(
                    context.watch<SupabaseService>().activePageColorKey,
                  ),
                ),
              ),
              SizedBox(height: 10),
              Text(
                'このセクションを読み込み中...',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD00303).withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: Color(0xFFD00303),
              size: 22,
            ),
            const SizedBox(height: 8),
            Text(
              'データを取得できませんでした',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '書籍が見つからないか、取得先が一時的に応答していません。',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('もう一度取得する'),
              ),
            ],
          ],
        ),
      );
    }

    // Page controls live outside the horizontal list so they remain visible
    // even when the nine cards fill (or overflow) the available width.
    return SizedBox(
      height: 252,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (canLoadPrevious)
            _buildCarouselPageButton(
              direction: AxisDirection.left,
              tooltip: '前の9冊に戻る',
              onPressed: isLoadingMore
                  ? null
                  : () {
                      scrollerKey.currentState?.registerUserInteraction();
                      onLoadPrevious();
                    },
            ),
          Expanded(
            child: _PagedBookScroller(
              key: scrollerKey,
              books: bookList,
              pageNumber: pageNumber,
              canLoadPrevious: canLoadPrevious,
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
              onLoadNext: onLoadMore,
              onLoadPrevious: onLoadPrevious,
              onBookTap: _showBookDetailDialog,
            ),
          ),
          if (hasMore || isLoadingMore)
            _buildCarouselPageButton(
              direction: AxisDirection.right,
              tooltip: '次の9冊を読み込む',
              onPressed: isLoadingMore
                  ? null
                  : () {
                      scrollerKey.currentState?.registerUserInteraction();
                      onLoadMore();
                    },
            ),
        ],
      ),
    );
  }

  Widget _buildCarouselPageButton({
    required AxisDirection direction,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 28,
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: InkResponse(
            onTap: onPressed,
            radius: 28,
            child: SizedBox(
              width: 28,
              height: 72,
              child: Center(
                child: CustomPaint(
                  size: const Size(22, 42),
                  painter: _CarouselTrianglePainter(direction),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_controller.userSearchMode) return _buildUserSearchResults();
    final results = _controller.visibleSearchResults;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            _controller.isSearching
                ? '検索中... (${results.length}件表示)'
                : '検索結果 (${results.length}件表示)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        if (_controller.isSearching)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (results.isEmpty)
          Container(
            height: 200,
            alignment: Alignment.center,
            child: Text(
              _controller.isSearching ? '検索しています...' : 'お探しの作品が見つかりませんでした。',
              style: TextStyle(color: Colors.grey[500]),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookSearchResults(books: results, onTap: _showBookDetailDialog),
              if (!_controller.isSearching &&
                  _controller.canLoadMoreSearchResults)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Align(
                    alignment: Alignment.center,
                    child: OutlinedButton.icon(
                      onPressed: _controller.loadMoreSearchResults,
                      icon: const Icon(Icons.expand_more),
                      label: const Text('さらに読み込む'),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildUserSearchResults() {
    final results = _controller.userSearchResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _controller.isSearching
                ? 'ユーザーを検索中...'
                : 'ユーザー検索結果（${results.length}件）',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'ユーザー名とユーザーIDのみを検索します。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        if (_controller.isSearching)
          const Center(child: CircularProgressIndicator())
        else if (results.isEmpty)
          const SizedBox(
            height: 180,
            child: Center(child: Text('該当するユーザーが見つかりませんでした。')),
          )
        else
          ...results.map(
            (profile) => Card(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _openUserProfile(profile.id),
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: Colors.black87,
                  backgroundImage: profile.avatarUrl.isEmpty
                      ? null
                      : NetworkImage(profile.avatarUrl),
                  child: profile.avatarUrl.isEmpty
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  profile.username,
                  style: const TextStyle(color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  profile.userId.isEmpty ? '' : '@${profile.userId}',
                  style: const TextStyle(color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: profile.isPrivate
                    ? const Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: Colors.black54,
                      )
                    : const Icon(Icons.chevron_right, color: Colors.black54),
              ),
            ),
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildTimeline({double? height, bool embedded = true}) {
    final accountColor = ProfilePageColors.colorFor(
      context.watch<SupabaseService>().activePageColorKey,
    );
    if (_controller.isLoadingTimeline && _controller.timelinePosts.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accountColor,
                ),
              ),
              const SizedBox(height: 10),
              const Text('タイムラインを読み込み中...'),
            ],
          ),
        ),
      );
    }

    if (_controller.timelinePosts.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'タイムラインの投稿がありません。',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      );
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final timelineHeight =
        height ??
        (MediaQuery.sizeOf(context).height * 0.58)
            .clamp(420.0, 600.0)
            .toDouble();

    final postCount = _controller.timelinePosts.length;
    // Genre separators use slots 0 and 1. Subsequent timeline ads receive
    // their own indices starting at 2, with no arbitrary page-wide cap.
    final adSlots = kIsWeb && timelineAdDisplayReady
        ? timelineAdSlotCount(postCount)
        : 0;

    final timeline = Scrollbar(
      controller: _timelineScrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _timelineScrollController,
        padding: EdgeInsets.fromLTRB(
          embedded ? 0 : 16,
          embedded ? 0 : 16,
          embedded ? 8 : 16,
          embedded ? 0 : 24,
        ),
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        // Insert ads after each configured number of posts, provided
        // another real post follows. No arbitrary per-page slot limit.
        // Change NINJA_ADMAX_POSTS_PER_AD to 5 for normal operation.
        itemCount: postCount + adSlots,
        itemBuilder: (context, index) {
          if (adSlots > 0 && isTimelineAdItem(index, postCount)) {
            return TimelineAdSlot(
              key: ValueKey('home-timeline-ad-slot-$index'),
              slotIndex:
                  homeTimelineAdSlotStart + index ~/ (timelinePostsPerAd + 1),
            );
          }
          final postIndex = adSlots > 0
              ? timelinePostIndexForItem(index, postCount)
              : index;
          final post = _controller.timelinePosts[postIndex];
          final currentProfileId = Provider.of<SupabaseService>(
            context,
            listen: false,
          ).activeProfileId;
          return PostCard(
            key: ValueKey(post.id),
            post: post,
            replies: _controller.timelineReplies[post.id] ?? const [],
            concealSpoiler: post.profileId != currentProfileId,
            onUserTap: () => _openUserProfile(post.profileId),
            onBookTap: () => _openBookFromPost(post),
            onReaction: post.profileId == currentProfileId
                ? null
                : (reaction) => _toggleReaction(post.id, reaction),
            onWantToRead: post.profileId == currentProfileId
                ? null
                : () => _toggleWantToReadFromPost(post),
            onReactionUsers: (reaction) =>
                _openEngagementUsers(post, reaction: reaction),
            onWantToReadUsers: () =>
                _openEngagementUsers(post, wantToRead: true),
            onDelete: post.profileId == currentProfileId
                ? () => _deletePost(post)
                : null,
            onEdit: post.profileId == currentProfileId
                ? () => _editPost(post)
                : null,
            onFavorite:
                FeatureFlags.favoritesUiEnabled &&
                    post.profileId == currentProfileId
                ? () => _toggleFavoriteFromPost(post)
                : null,
            onReport: post.profileId == currentProfileId
                ? null
                : () => _reportPost(post.id),
            onReply: (parentReply) => _replyToPost(post, parentReply),
            onReplyReport: _reportReply,
            concealReplySpoiler: (reply) {
              final profileId = Provider.of<SupabaseService>(
                context,
                listen: false,
              ).activeProfileId;
              return profileId.isEmpty || reply.profileId != profileId;
            },
            canReportReply: (reply) {
              final profileId = Provider.of<SupabaseService>(
                context,
                listen: false,
              ).activeProfileId;
              return profileId.isEmpty || reply.profileId != profileId;
            },
            onReplyUserTap: _openUserProfile,
            onRepliesChanged: () => _controller.loadData(context),
          );
        },
      ),
    );

    if (!embedded) {
      return SizedBox(height: timelineHeight, child: timeline);
    }

    return Container(
      height: timelineHeight,
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.45)
              : Colors.black,
          width: 1.5,
        ),
      ),
      child: timeline,
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.only(top: 40, bottom: 30),
      alignment: Alignment.center,
      child: Column(
        children: [
          Divider(color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            '© 2026 Sharemarium. All rights reserved.',
            style: TextStyle(color: Colors.grey[400], fontSize: 11),
          ),
          const SizedBox(height: 8),
          const CatalogCredit(),
          const SizedBox(height: 4),
          Text(
            'Powered by Supabase & PostgreSQL',
            style: TextStyle(color: Colors.grey[400], fontSize: 9),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 2,
            children: [
              _footerLink('プライバシー', '/privacy'),
              _footerLink('利用規約', '/terms'),
              _footerLink('ガイドライン', '/community-guidelines'),
              _footerLink('権利侵害・通報', '/infringement-policy'),
              _footerLink('外部送信', '/external-transmission'),
              _footerLink('お問い合わせ', '/contact'),
              _footerLink('運営者情報', '/about'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footerLink(String label, String route) {
    return TextButton(
      onPressed: () => Navigator.of(context).pushNamed(route),
      style: TextButton.styleFrom(
        foregroundColor: Colors.grey[600],
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}

class _BookPostsPanel extends StatefulWidget {
  const _BookPostsPanel({
    required this.bookId,
    required this.onUserTap,
    required this.onReaction,
    required this.onReport,
    required this.onReply,
    required this.onReplyReport,
  });

  final String bookId;
  final Future<void> Function(String profileId) onUserTap;
  final Future<void> Function(Post post, PostReactionType reaction) onReaction;
  final Future<void> Function(Post post) onReport;
  final Future<void> Function(Post post, PostReply? parentReply) onReply;
  final Future<void> Function(PostReply reply) onReplyReport;

  @override
  State<_BookPostsPanel> createState() => _BookPostsPanelState();
}

class _BookPostsPanelState extends State<_BookPostsPanel> {
  final ScrollController _scrollController = ScrollController();
  List<Post> _posts = const [];
  Map<String, List<PostReply>> _replies = const {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant _BookPostsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _isLoading = true);
    final service = Provider.of<SupabaseService>(context, listen: false);
    final posts = await service.fetchPostsForBook(widget.bookId);
    final replies = await service.fetchRepliesForPosts(
      posts.map((post) => post.id).toList(growable: false),
    );
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _replies = replies;
      _isLoading = false;
    });
  }

  Future<void> _toggleReaction(Post post, PostReactionType reaction) async {
    final index = _posts.indexWhere((candidate) => candidate.id == post.id);
    if (index < 0) return;
    final optimisticPosts = List<Post>.from(_posts);
    optimisticPosts[index] = post.withToggledReaction(reaction);
    setState(() => _posts = optimisticPosts);
    await widget.onReaction(post, reaction);
    if (mounted) await _load(showLoading: false);
  }

  Future<void> _toggleWantToRead(Post post) async {
    final index = _posts.indexWhere((candidate) => candidate.id == post.id);
    if (index < 0) return;
    final optimistic = List<Post>.from(_posts);
    optimistic[index] = post.withToggledWantToRead();
    setState(() => _posts = optimistic);
    final service = Provider.of<SupabaseService>(context, listen: false);
    final result = await service.toggleWantToRead(
      book: Book(
        id: post.bookId,
        title: post.bookTitle,
        author: post.bookAuthor,
        publisher: '',
        pubDate: '',
        isbn: post.bookId,
        coverUrl: post.bookCoverUrl,
      ),
      sourcePostId: post.id,
    );
    if (!mounted) return;
    if (result == WantToReadToggleResult.subscriptionRequired) {
      setState(() {
        final current = List<Post>.from(_posts);
        current[index] = post;
        _posts = current;
      });
      await showSubscriptionLockedDialog(
        context: context,
        featureLabel: '「読みたい！」',
      );
      return;
    }
    if (result.shouldRestoreOptimisticState) {
      setState(() {
        final current = List<Post>.from(_posts);
        current[index] = post;
        _posts = current;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _showEngagementUsers(
    Post post, {
    PostReactionType? reaction,
    bool wantToRead = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => PostEngagementUsersScreen(
          postId: post.id,
          title: wantToRead ? '「読みたい！」したユーザー' : '${reaction!.symbol}したユーザー',
          reaction: reaction,
          wantToRead: wantToRead,
          onProfileTap: (profile) {
            Navigator.of(routeContext).pop();
            widget.onUserTap(profile.id);
          },
        ),
      ),
    );
  }

  Future<void> _reply(Post post, PostReply? parentReply) async {
    await widget.onReply(post, parentReply);
    if (mounted) await _load(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final panelHeight = (MediaQuery.sizeOf(context).height * 0.58)
        .clamp(420.0, 560.0)
        .toDouble();

    return Container(
      height: panelHeight,
      padding: const EdgeInsets.fromLTRB(10, 12, 6, 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black : Colors.white,
        border: Border.all(
          color: isDarkMode ? Colors.white : Colors.black,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8, bottom: 10),
            child: Text(
              'この本の投稿',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                ? Center(
                    child: Text(
                      'この本に関する投稿はまだありません。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: RefreshIndicator(
                      onRefresh: () => _load(showLoading: false),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 8),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          final post = _posts[index];
                          final service = Provider.of<SupabaseService>(
                            context,
                            listen: false,
                          );
                          final currentProfileId = service.activeProfileId;
                          return PostCard(
                            key: ValueKey('book-${post.id}'),
                            post: post,
                            replies: _replies[post.id] ?? const [],
                            concealSpoiler: post.profileId != currentProfileId,
                            concealReplySpoiler: (reply) =>
                                reply.profileId != currentProfileId,
                            onUserTap: () => widget.onUserTap(post.profileId),
                            onReaction: post.profileId == currentProfileId
                                ? null
                                : (reaction) => _toggleReaction(post, reaction),
                            onWantToRead: post.profileId == currentProfileId
                                ? null
                                : () => _toggleWantToRead(post),
                            onReactionUsers: (reaction) =>
                                _showEngagementUsers(post, reaction: reaction),
                            onWantToReadUsers: () =>
                                _showEngagementUsers(post, wantToRead: true),
                            onReport: post.profileId == currentProfileId
                                ? null
                                : () => widget.onReport(post),
                            onReply: (parentReply) => _reply(post, parentReply),
                            onReplyReport: widget.onReplyReport,
                            canReportReply: (reply) =>
                                currentProfileId.isEmpty ||
                                reply.profileId != currentProfileId,
                            onReplyUserTap: widget.onUserTap,
                            onRepliesChanged: () => _load(showLoading: false),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PagedBookScroller extends StatefulWidget {
  const _PagedBookScroller({
    super.key,
    required this.books,
    required this.pageNumber,
    required this.canLoadPrevious,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadNext,
    required this.onLoadPrevious,
    required this.onBookTap,
  });

  final List<Book> books;
  final int pageNumber;
  final bool canLoadPrevious;
  final bool hasMore;
  final bool isLoadingMore;
  final Future<void> Function() onLoadNext;
  final VoidCallback onLoadPrevious;
  final Future<void> Function(Book) onBookTap;

  @override
  State<_PagedBookScroller> createState() => _PagedBookScrollerState();
}

class _PagedBookScrollerState extends State<_PagedBookScroller> {
  final ScrollController _scrollController = ScrollController();
  late final BookCarouselAutoAdvance _autoAdvance;
  bool _pageChangePending = false;
  bool _landAtEndAfterChange = false;
  bool _isRepositioningAfterPageChange = false;
  bool _isAutoScrolling = false;
  bool _appending = false;
  late List<Book> _buffer;
  double _overscrollDistance = 0;

  @override
  void initState() {
    super.initState();
    _buffer = List.of(widget.books);
    _autoAdvance = BookCarouselAutoAdvance(onAdvance: _advanceAutomatically)
      ..start();
  }

  void registerUserInteraction() {
    _autoAdvance.registerUserInteraction();
    if (_isAutoScrolling && _scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.offset);
    }
  }

  void pauseForBookDetail() => _autoAdvance.pauseForBookDetail();

  void resumeAfterBookDetail() => _autoAdvance.resumeAfterBookDetail();

  @override
  void didUpdateWidget(covariant _PagedBookScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber) {
      _pageChangePending = false;
      if (_appending) {
        final ids = _buffer.map((book) => book.id).toSet();
        _buffer.addAll(widget.books.where((book) => ids.add(book.id)));
        return;
      }
      _buffer = List.of(widget.books);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final target = _landAtEndAfterChange
            ? _scrollController.position.maxScrollExtent
            : _scrollController.position.minScrollExtent;
        _isRepositioningAfterPageChange = true;
        _scrollController
            .animateTo(
              target,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (mounted) _isRepositioningAfterPageChange = false;
            });
        _landAtEndAfterChange = false;
      });
    } else if (oldWidget.isLoadingMore && !widget.isLoadingMore) {
      _pageChangePending = false;
    } else if (!identical(oldWidget.books, widget.books) && !_appending) {
      _buffer = List.of(widget.books);
    }
  }

  @override
  void dispose() {
    _autoAdvance.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _advanceAutomatically() async {
    if (!mounted ||
        (widget.isLoadingMore && !_appending) ||
        (_pageChangePending && !_appending) ||
        _isAutoScrolling ||
        ModalRoute.of(context)?.isCurrent != true ||
        !_scrollController.hasClients ||
        !_isVisibleOnScreen()) {
      return;
    }

    if (await _moveOneBook()) {
      // Keep the 1.5-second visual cadence independent from network latency.
      // Loading the next nine books continues in the background while the
      // already buffered books keep moving.
      unawaited(_prefetchNextPageIfNeeded());
      return;
    }

    // Do not wrap back to the beginning while the next batch is still in
    // flight. The following timer tick continues as soon as cards are added.
    if (_appending) return;

    // A very wide viewport can initially fit all nine books. In that case a
    // new batch is needed before there is any horizontal distance to move.
    if (widget.hasMore && !_appending) {
      await _prefetchNextPageIfNeeded(force: true);
      if (mounted &&
          !_autoAdvance.isPaused &&
          ModalRoute.of(context)?.isCurrent == true &&
          _isVisibleOnScreen()) {
        await _moveOneBook();
      }
      return;
    }

    final position = _scrollController.position;
    if (position.extentBefore > 1) {
      _isAutoScrolling = true;
      try {
        await _scrollController.animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      } finally {
        _isAutoScrolling = false;
      }
    }
  }

  Future<bool> _moveOneBook() async {
    if (!mounted || !_scrollController.hasClients) return false;
    final position = _scrollController.position;
    if (position.extentAfter <= 1) return false;

    const step = 150.0; // 138px cover plus 12px spacing.
    final target = ((position.pixels / step).floor() * step + step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _isAutoScrolling = true;
    try {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    } finally {
      _isAutoScrolling = false;
    }
    return true;
  }

  Future<void> _prefetchNextPageIfNeeded({bool force = false}) async {
    if (!mounted ||
        _appending ||
        !widget.hasMore ||
        !_scrollController.hasClients) {
      return;
    }
    const step = 150.0;
    final firstVisible = (_scrollController.position.pixels / step).floor();
    if (!force && _buffer.length - firstVisible > 9) return;

    _appending = true;
    try {
      await _loadNextPage();
      // didUpdateWidget consumes the new page on the next frame.
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      _appending = false;
    }
  }

  bool _isVisibleOnScreen() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottom = topLeft.dy + renderObject.size.height;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    return bottom > 0 && topLeft.dy < viewportHeight;
  }

  Future<void> _loadNextPage() async {
    if (_pageChangePending || widget.isLoadingMore || !widget.hasMore) return;
    _pageChangePending = true;
    _landAtEndAfterChange = false;
    await widget.onLoadNext();
    if (mounted && !widget.isLoadingMore) _pageChangePending = false;
  }

  void _loadPreviousPage() {
    if (_pageChangePending || widget.isLoadingMore || !widget.canLoadPrevious) {
      return;
    }
    _pageChangePending = true;
    _landAtEndAfterChange = true;
    widget.onLoadPrevious();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;
    final isUserDriven =
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        notification is OverscrollNotification;
    if (isUserDriven && !_isAutoScrolling && !_isRepositioningAfterPageChange) {
      registerUserInteraction();
    }
    if (notification is ScrollStartNotification) {
      _overscrollDistance = 0;
    } else if (notification is OverscrollNotification) {
      _overscrollDistance += notification.overscroll;
      if (_overscrollDistance >= 12) {
        _loadNextPage();
        _overscrollDistance = 0;
      } else if (_overscrollDistance <= -12) {
        _loadPreviousPage();
        _overscrollDistance = 0;
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        notification.scrollDelta != null) {
      final delta = notification.scrollDelta!;
      if (delta > 0 && notification.metrics.extentAfter <= 0.5) {
        _loadNextPage();
      } else if (delta < 0 && notification.metrics.extentBefore <= 0.5) {
        _loadPreviousPage();
      }
    } else if (notification is ScrollEndNotification &&
        !_isRepositioningAfterPageChange &&
        !_isAutoScrolling) {
      if (notification.metrics.extentAfter <= 0.5 &&
          notification.metrics.extentBefore > 0.5) {
        _loadNextPage();
      } else if (notification.metrics.extentBefore <= 0.5 &&
          notification.metrics.extentAfter > 0.5) {
        _loadPreviousPage();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: _buffer.length,
      itemBuilder: (context, index) => BookCard(
        book: _buffer[index],
        marginRight: index == _buffer.length - 1 ? 0 : 12,
        onTap: () async {
          pauseForBookDetail();
          try {
            await widget.onBookTap(_buffer[index]);
          } finally {
            resumeAfterBookDetail();
          }
        },
      ),
    );

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: widget.isLoadingMore && !_appending,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: list,
                  ),
                ),
              ),
              if (widget.isLoadingMore && !_appending)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(
                      context,
                    ).scaffoldBackgroundColor.withValues(alpha: 0.7),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: ProfilePageColors.colorFor(
                          context.watch<SupabaseService>().activePageColorKey,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CarouselTrianglePainter extends CustomPainter {
  const _CarouselTrianglePainter(this.direction);

  final AxisDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (direction == AxisDirection.left) {
      canvas
        ..save()
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }

    const radius = 3.5;
    final path = Path();
    path
      ..moveTo(radius, 0)
      ..lineTo(size.width - radius, size.height / 2 - radius)
      ..quadraticBezierTo(
        size.width,
        size.height / 2,
        size.width - radius,
        size.height / 2 + radius,
      )
      ..lineTo(radius, size.height - radius)
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFD00303));
    if (direction == AxisDirection.left) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CarouselTrianglePainter oldDelegate) =>
      oldDelegate.direction != direction;
}

class _DiagonalRedClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.33, 0)
      ..lineTo(size.width * 0.47, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
