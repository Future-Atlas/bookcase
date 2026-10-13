import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/rakuten_api.dart';
import '../models/book.dart';
import '../models/featured_book.dart';
import '../services/supabase_service.dart';

class FeaturedBooksAdminPanel extends StatefulWidget {
  const FeaturedBooksAdminPanel({super.key});

  @override
  State<FeaturedBooksAdminPanel> createState() =>
      _FeaturedBooksAdminPanelState();
}

class _FeaturedBooksAdminPanelState extends State<FeaturedBooksAdminPanel> {
  final TextEditingController _searchController = TextEditingController();
  List<FeaturedBook> _featured = const [];
  List<Book> _results = const [];
  bool _loading = true;
  bool _searching = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = context.read<SupabaseService>();
    final featured = await service.fetchFeaturedBooks(includeScheduled: true);
    if (!mounted) return;
    setState(() {
      _featured = featured;
      _loading = false;
    });
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() => _searching = true);
    final results = await RakutenApi.searchByKeyword(
      keyword: query,
      page: 1,
      count: 20,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _editBook(Book book, {FeaturedBook? existing}) async {
    DateTime? startsAt = existing?.startsAt?.toLocal();
    DateTime? endsAt = existing?.endsAt?.toLocal();
    final relatedController = TextEditingController(
      text: existing?.relatedScreenTitles.join('\n') ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '注目書籍に追加' : '注目書籍を編集'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    book.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(book.author),
                  const SizedBox(height: 16),
                  TextField(
                    controller: relatedController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '実在する映像化作品名（任意・1行に1作品）',
                      helperText: '書籍との関係を確認できる作品だけ入力してください。',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final value = await showDatePicker(
                            context: dialogContext,
                            initialDate: startsAt ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2100),
                          );
                          if (value != null) {
                            setDialogState(() => startsAt = value);
                          }
                        },
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(
                          startsAt == null
                              ? '掲載開始日を設定'
                              : '開始 ${_dateLabel(startsAt!)}',
                        ),
                      ),
                      if (startsAt != null)
                        IconButton(
                          tooltip: '掲載開始日を解除',
                          onPressed: () =>
                              setDialogState(() => startsAt = null),
                          icon: const Icon(Icons.clear),
                        ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final value = await showDatePicker(
                            context: dialogContext,
                            initialDate: endsAt ?? startsAt ?? DateTime.now(),
                            firstDate: startsAt ?? DateTime(2024),
                            lastDate: DateTime(2100),
                          );
                          if (value != null) {
                            setDialogState(
                              () => endsAt = value.add(const Duration(days: 1)),
                            );
                          }
                        },
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(
                          endsAt == null
                              ? '掲載終了日を設定'
                              : '終了 ${_dateLabel(endsAt!)}',
                        ),
                      ),
                      if (endsAt != null)
                        IconButton(
                          tooltip: '掲載終了日を解除',
                          onPressed: () => setDialogState(() => endsAt = null),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final relatedTitles = relatedController.text
        .split(RegExp(r'[\r\n]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    relatedController.dispose();
    if (accepted != true || !mounted) return;

    setState(() => _saving = true);
    final success = await context.read<SupabaseService>().adminSaveFeaturedBook(
      book: book,
      startsAt: startsAt,
      endsAt: endsAt,
      relatedScreenTitles: relatedTitles,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(success, success ? '注目書籍を保存しました。' : '注目書籍を保存できませんでした。');
    if (success) await _load();
  }

  Future<void> _remove(FeaturedBook item) async {
    final success = await context
        .read<SupabaseService>()
        .adminRemoveFeaturedBook(item.id);
    if (!mounted) return;
    _showResult(success, success ? '注目書籍から解除しました。' : '解除できませんでした。');
    if (success) await _load();
  }

  Future<void> _move(int index, int delta) async {
    final next = index + delta;
    if (next < 0 || next >= _featured.length) return;
    final reordered = List<FeaturedBook>.from(_featured);
    final item = reordered.removeAt(index);
    reordered.insert(next, item);
    setState(() => _featured = reordered);
    final success = await context
        .read<SupabaseService>()
        .adminReorderFeaturedBooks(reordered);
    if (!mounted) return;
    if (!success) {
      _showResult(false, '表示順を保存できませんでした。');
      await _load();
    }
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? null : Colors.red,
      ),
    );
  }

  static String _dateLabel(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('featured-books-admin-panel'),
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '注目書籍の管理',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text('検索して追加し、矢印でトップページの表示順を変更できます。'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      labelText: 'タイトル・著者・出版社で検索',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('検索'),
                ),
              ],
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._results
                  .take(10)
                  .map(
                    (book) => ListTile(
                      leading: book.coverUrl.isEmpty
                          ? const Icon(Icons.book_outlined)
                          : Image.network(
                              book.coverUrl,
                              width: 36,
                              fit: BoxFit.cover,
                            ),
                      title: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(book.author, maxLines: 1),
                      trailing: IconButton(
                        tooltip: '注目書籍に追加',
                        onPressed: _saving ? null : () => _editBook(book),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ),
                  ),
            ],
            const Divider(height: 28),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_featured.isEmpty)
              const Text('登録済みの注目書籍はありません。')
            else
              ..._featured.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text('${index + 1}'),
                  title: Text(item.book.title),
                  subtitle: Text(
                    [
                      item.book.author,
                      if (item.startsAt != null)
                        '開始 ${_dateLabel(item.startsAt!.toLocal())}',
                      if (item.endsAt != null)
                        '終了 ${_dateLabel(item.endsAt!.toLocal())}',
                    ].where((value) => value.isNotEmpty).join(' ／ '),
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: '上へ',
                        onPressed: index == 0 ? null : () => _move(index, -1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: '下へ',
                        onPressed: index == _featured.length - 1
                            ? null
                            : () => _move(index, 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: '編集',
                        onPressed: () => _editBook(item.book, existing: item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: '解除',
                        onPressed: () => _remove(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
