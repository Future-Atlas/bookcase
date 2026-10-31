import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/feature_flags.dart';
import '../models/book.dart';
import '../models/post.dart';
import '../models/post_reply.dart';
import '../models/social_models.dart';
import '../screens/post_engagement_users_screen.dart';
import '../services/supabase_service.dart';
import 'book_action_label.dart';
import 'favorite_replacement_dialog.dart';
import 'post_card.dart';
import 'post_reply_dialog.dart';
import 'rakuten_book_link.dart';

typedef BookPostReactionCallback =
    Future<void> Function(Post post, PostReactionType reaction);

/// The single book-detail surface used from Home, search results and profiles.
///
/// [preferredProfileId] only changes the order of reviews. This lets a profile
/// owner appear first without creating a second, reduced book-detail screen.
class BookDetailDialog extends StatefulWidget {
  const BookDetailDialog({
    super.key,
    required this.book,
    required this.onRead,
    required this.ensureAuthenticated,
    required this.onUserTap,
    required this.onReaction,
    required this.onReport,
    required this.onReply,
    required this.onReplyReport,
    this.onDataChanged,
    this.preferredProfileId,
  });

  final Book book;
  final Future<void> Function() onRead;
  final Future<bool> Function() ensureAuthenticated;
  final Future<void> Function(String profileId) onUserTap;
  final BookPostReactionCallback onReaction;
  final Future<void> Function(Post post) onReport;
  final Future<void> Function(Post post, PostReply? parentReply) onReply;
  final Future<void> Function(PostReply reply) onReplyReport;
  final Future<void> Function()? onDataChanged;
  final String? preferredProfileId;

  @override
  State<BookDetailDialog> createState() => _BookDetailDialogState();
}

class _BookDetailDialogState extends State<BookDetailDialog> {
  late Future<bool> _isReadFuture;
  Future<bool>? _isFavoriteFuture;
  late Future<bool> _isWantedFuture;

  @override
  void initState() {
    super.initState();
    _refreshBookState();
  }

  void _refreshBookState() {
    final service = Provider.of<SupabaseService>(context, listen: false);
    _isReadFuture = service.isBookReadByCurrentUser(bookId: widget.book.id);
    _isFavoriteFuture = FeatureFlags.favoritesUiEnabled
        ? service.isBookFavoritedByCurrentUser(widget.book.id)
        : null;
    _isWantedFuture = FeatureFlags.wantToReadUiEnabled
        ? service.isBookWantedByCurrentUser(widget.book.id)
        : Future<bool>.value(false);
  }

  Future<void> _toggleWantToRead() async {
    if (!await widget.ensureAuthenticated() || !mounted) return;
    final service = Provider.of<SupabaseService>(context, listen: false);
    final result = await service.toggleWantToRead(book: widget.book);
    if (!mounted) return;
    if (result == WantToReadToggleResult.subscriptionRequired) {
      await showSubscriptionLockedDialog(
        context: context,
        featureLabel: '「読みたい！」',
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
    if (!result.shouldRestoreOptimisticState) {
      setState(_refreshBookState);
      await widget.onDataChanged?.call();
    }
  }

  Future<void> _toggleFavorite() async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    final result = await service.toggleFavorite(widget.book.id);
    if (!mounted) return;

    if (result == FavoriteToggleResult.standardLimitReached ||
        result == FavoriteToggleResult.subscriberLimitReached) {
      final replaced = await showFavoriteReplacementDialog(
        context: context,
        targetBookId: widget.book.id,
        targetBookTitle: widget.book.title,
      );
      if (!mounted || !replaced) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('お気に入りを入れ替えました。')));
      setState(_refreshBookState);
      await widget.onDataChanged?.call();
      return;
    }

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
    if (result == FavoriteToggleResult.added ||
        result == FavoriteToggleResult.removed) {
      setState(_refreshBookState);
      await widget.onDataChanged?.call();
    }
  }

  Widget _missingCover() {
    return Container(
      color: Colors.grey[300],
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.menu_book, size: 28, color: Colors.black54),
          const SizedBox(height: 8),
          Text(
            widget.book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            widget.book.author,
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
    final book = widget.book;
    final hasCover = book.coverUrl.trim().isNotEmpty;
    return Dialog(
      backgroundColor: const Color(0xFFE6E6E6),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                    child: Container(
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
                              errorBuilder: (_, _, _) => _missingCover(),
                            )
                          : _missingCover(),
                    ),
                  );

                  final detailBlock = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FutureBuilder<bool>(
                        future: _isReadFuture,
                        builder: (context, snapshot) {
                          final isRead = snapshot.data ?? false;
                          final checking =
                              snapshot.connectionState ==
                              ConnectionState.waiting;
                          return Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 64,
                                  child: ElevatedButton(
                                    onPressed: isRead || checking
                                        ? null
                                        : () async {
                                            Navigator.of(context).pop();
                                            await widget.onRead();
                                          },
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
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (FeatureFlags.wantToReadUiEnabled) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FutureBuilder<bool>(
                                    future: _isWantedFuture,
                                    builder: (context, snapshot) {
                                      final wanted = snapshot.data ?? false;
                                      final checking =
                                          snapshot.connectionState ==
                                          ConnectionState.waiting;
                                      return SizedBox(
                                        height: 64,
                                        child: ElevatedButton(
                                          onPressed: checking
                                              ? null
                                              : _toggleWantToRead,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.black,
                                            foregroundColor: Colors.amber,
                                            disabledBackgroundColor:
                                                Colors.black,
                                            disabledForegroundColor:
                                                Colors.amber.shade200,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: BookActionLabel(
                                            bookId: book.id,
                                            label: wanted ? '読みたい！済み' : '読みたい！',
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
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      if (FeatureFlags.favoritesUiEnabled)
                        FutureBuilder<bool>(
                          future: _isFavoriteFuture,
                          builder: (context, snapshot) {
                            final favorite = snapshot.data ?? false;
                            return Align(
                              child: OutlinedButton.icon(
                                onPressed:
                                    snapshot.connectionState ==
                                        ConnectionState.waiting
                                    ? null
                                    : _toggleFavorite,
                                icon: Icon(
                                  favorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: const Color(0xFFD00303),
                                ),
                                label: Text(favorite ? 'お気に入り解除' : 'お気に入りに登録'),
                              ),
                            );
                          },
                        ),
                      Row(
                        children: [
                          ...List.generate(
                            5,
                            (index) => Icon(
                              index < book.ratingAvg.floor()
                                  ? Icons.star
                                  : Icons.star_border,
                              color: const Color(0xFFE0B400),
                              size: isNarrow ? 30 : 42,
                            ),
                          ),
                          SizedBox(width: isNarrow ? 8 : 12),
                          Text(
                            book.ratingAvg.toStringAsFixed(1),
                            style: TextStyle(
                              color: const Color(0xFFE0B400),
                              fontSize: isNarrow ? 20 : 26,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        book.title.trim().isEmpty ? 'タイトル不明' : book.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        book.author.trim().isEmpty ? '著者不明' : book.author,
                        style: TextStyle(color: Colors.grey[800], fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        book.publisher.trim().isEmpty
                            ? '出版社不明'
                            : book.publisher,
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
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
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      isNarrow
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
                            ),
                      RakutenBookLink(book: book),
                      const SizedBox(height: 20),
                      BookPostsPanel(
                        bookId: book.id,
                        preferredProfileId: widget.preferredProfileId,
                        onUserTap: widget.onUserTap,
                        onReaction: widget.onReaction,
                        onReport: widget.onReport,
                        onReply: widget.onReply,
                        onReplyReport: widget.onReplyReport,
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
  }
}

class BookPostsPanel extends StatefulWidget {
  const BookPostsPanel({
    super.key,
    required this.bookId,
    required this.onUserTap,
    required this.onReaction,
    required this.onReport,
    required this.onReply,
    required this.onReplyReport,
    this.preferredProfileId,
  });

  final String bookId;
  final String? preferredProfileId;
  final Future<void> Function(String profileId) onUserTap;
  final BookPostReactionCallback onReaction;
  final Future<void> Function(Post post) onReport;
  final Future<void> Function(Post post, PostReply? parentReply) onReply;
  final Future<void> Function(PostReply reply) onReplyReport;

  @override
  State<BookPostsPanel> createState() => _BookPostsPanelState();
}

class _BookPostsPanelState extends State<BookPostsPanel> {
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
  void didUpdateWidget(covariant BookPostsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.preferredProfileId != widget.preferredProfileId) {
      _load();
    }
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
    final posts = await service.fetchPostsForBook(
      widget.bookId,
      preferredProfileId: widget.preferredProfileId,
    );
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
    setState(() {
      final optimistic = List<Post>.from(_posts);
      optimistic[index] = post.withToggledReaction(reaction);
      _posts = optimistic;
    });
    await widget.onReaction(post, reaction);
    if (mounted) await _load(showLoading: false);
  }

  Future<void> _toggleWantToRead(Post post) async {
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
      await showSubscriptionLockedDialog(
        context: context,
        featureLabel: '「読みたい！」',
      );
    } else if (result.shouldRestoreOptimisticState) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
    await _load(showLoading: false);
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final currentProfileId = Provider.of<SupabaseService>(
      context,
      listen: false,
    ).activeProfileId;
    final panelHeight = (MediaQuery.sizeOf(context).height * 0.58)
        .clamp(420.0, 560.0)
        .toDouble();
    return Container(
      height: panelHeight,
      padding: const EdgeInsets.fromLTRB(10, 12, 6, 8),
      decoration: BoxDecoration(
        color: dark ? Colors.black : Colors.white,
        border: Border.all(
          color: dark ? Colors.white : Colors.black,
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
                color: dark ? Colors.white : Colors.black,
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
                      style: TextStyle(
                        color: dark ? Colors.white70 : Colors.black54,
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
                          final own = post.profileId == currentProfileId;
                          return PostCard(
                            key: ValueKey('book-${post.id}'),
                            post: post,
                            replies: _replies[post.id] ?? const [],
                            concealSpoiler: !own,
                            concealReplySpoiler: (reply) =>
                                reply.profileId != currentProfileId,
                            onUserTap: () => widget.onUserTap(post.profileId),
                            onReaction: own
                                ? null
                                : (reaction) => _toggleReaction(post, reaction),
                            onWantToRead: own
                                ? null
                                : () => _toggleWantToRead(post),
                            onReactionUsers: (reaction) =>
                                _showEngagementUsers(post, reaction: reaction),
                            onWantToReadUsers: () =>
                                _showEngagementUsers(post, wantToRead: true),
                            onReport: own ? null : () => widget.onReport(post),
                            onReply: (parentReply) async {
                              await widget.onReply(post, parentReply);
                              if (mounted) await _load(showLoading: false);
                            },
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
