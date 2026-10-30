import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/moderation_models.dart';
import '../services/supabase_service.dart';
import '../widgets/featured_books_admin_panel.dart';
import '../widgets/private_account_admin_panel.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  List<ModerationReport> _reports = [];
  bool _loading = true;
  int? _processingReportId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final service = Provider.of<SupabaseService>(context, listen: false);
    final reports = await service.fetchModerationReports();
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _loading = false;
    });
  }

  Future<void> _deletePost(ModerationReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('投稿を削除しますか？'),
        content: const Text('この操作を行うと、投稿は利用者の画面から削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(
      report,
      (service) => service.adminDeleteReportedPost(report.id),
      successMessage: '投稿を削除しました。',
    );
  }

  Future<void> _deleteReply(ModerationReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('返信を削除しますか？'),
        content: const Text('この操作を行うと、対象の返信とその返信先の会話が削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(
      report,
      (service) => service.adminDeleteReportedReply(report.id),
      successMessage: '返信を削除しました。',
    );
  }

  Future<void> _changeSuspension(ModerationReport report) async {
    var reason = '利用規約又はコミュニティガイドライン違反';
    if (!report.reportedAccountSuspended) {
      final controller = TextEditingController(text: reason);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('アカウントを停止しますか？'),
          content: TextField(
            controller: controller,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '停止理由',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('停止'),
            ),
          ],
        ),
      );
      reason = controller.text.trim();
      controller.dispose();
      if (confirmed != true || !mounted) return;
    }

    final suspend = !report.reportedAccountSuspended;
    await _runAction(
      report,
      (service) => service.adminSetAccountSuspension(
        profileId: report.reportedProfileId,
        suspended: suspend,
        reason: reason,
      ),
      successMessage: suspend ? 'アカウントを停止しました。' : 'アカウント停止を解除しました。',
    );
  }

  Future<void> _dismissReport(ModerationReport report) async {
    await _runAction(
      report,
      (service) => service.adminResolveReport(report.id),
      successMessage: '報告を「対応不要」として処理しました。',
    );
  }

  Future<void> _deleteAccount(ModerationReport report) async {
    final reasonController = TextEditingController(text: '重大又は反復的な利用規約違反');
    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('アカウントを完全に削除しますか？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'この操作は元に戻せません。アカウントと関連データを削除し、'
                  '不正な再登録を防ぐため、氏名・生年月日とメールアドレス又は電話番号の'
                  '組み合わせから作成した復元できない照合値を3年間保存します。',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '削除理由',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmationController,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: '確認のため「削除」と入力',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: confirmationController.text == '削除'
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.red[800]),
              child: const Text('完全に削除'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    confirmationController.dispose();
    if (confirmed != true || !mounted) return;
    await _runAction(
      report,
      (service) => service.adminDeleteAccount(
        profileId: report.reportedProfileId,
        reason: reason,
      ),
      successMessage: 'アカウントを削除し、再登録防止情報を保存しました。',
    );
  }

  Future<void> _runAction(
    ModerationReport report,
    Future<bool> Function(SupabaseService service) action, {
    required String successMessage,
  }) async {
    setState(() => _processingReportId = report.id);
    final service = Provider.of<SupabaseService>(context, listen: false);
    final success = await action(service);
    if (!mounted) return;
    setState(() => _processingReportId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? successMessage : '処理に失敗しました。管理者権限を確認してください。'),
      ),
    );
    if (success) await _load();
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FeaturedBooksAdminPanel(),
          const PrivateAccountAdminPanel(),
          const Text(
            '報告管理',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_reports.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: Text('報告はありません。')),
            )
          else
            ..._reports.map(_buildReportCard),
        ],
      ),
    );
  }

  Widget _buildReportCard(ModerationReport report) {
    final processing = _processingReportId == report.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(report.isOpen ? '未対応' : '対応済み'),
                  backgroundColor: report.isOpen
                      ? Colors.red.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.category.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  _formatDate(report.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('報告者：${report.reporterUsername}'),
            Text(
              '対象：${report.reportedUsername}'
              '${report.reportedAccountSuspended ? '（停止中）' : ''}',
            ),
            if (report.reportedUserId.isNotEmpty)
              Text('ユーザーID：@${report.reportedUserId}'),
            if (report.bookId.isNotEmpty) Text('書籍ID：${report.bookId}'),
            if (report.targetsReply) ...[
              const SizedBox(height: 8),
              const Text(
                '報告対象の返信',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  report.replyMessage.isEmpty
                      ? '（削除済みの返信）'
                      : report.replyMessage,
                ),
              ),
            ],
            if (report.review.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(report.review),
              ),
            ],
            if (report.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('補足：${report.details}'),
            ],
            if (!report.isOpen && report.resolution.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('処理：${report.resolution}'),
            ],
            if (report.isOpen) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (report.targetsReply)
                    FilledButton.icon(
                      onPressed: processing || report.replyId == null
                          ? null
                          : () => _deleteReply(report),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('返信削除'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: processing || report.postId == null
                          ? null
                          : () => _deletePost(report),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('投稿削除'),
                    ),
                  OutlinedButton.icon(
                    onPressed: processing || report.reportedProfileId.isEmpty
                        ? null
                        : () => _changeSuspension(report),
                    icon: Icon(
                      report.reportedAccountSuspended
                          ? Icons.lock_open
                          : Icons.person_off_outlined,
                    ),
                    label: Text(
                      report.reportedAccountSuspended ? '停止解除' : 'アカウント停止',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: processing || report.reportedProfileId.isEmpty
                        ? null
                        : () => _deleteAccount(report),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red[900],
                    ),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('アカウント削除'),
                  ),
                  TextButton(
                    onPressed: processing ? null : () => _dismissReport(report),
                    child: const Text('対応不要'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
