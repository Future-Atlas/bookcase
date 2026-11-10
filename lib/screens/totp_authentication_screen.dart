import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/supabase_service.dart';
import '../utils/japanese_datetime.dart';
import '../utils/text_field_clipboard.dart';
import 'contact_screen.dart';

class TotpEnrollmentScreen extends StatefulWidget {
  const TotpEnrollmentScreen({
    super.key,
    required this.onCompleted,
    this.allowClose = false,
  });

  final VoidCallback onCompleted;
  final bool allowClose;

  @override
  State<TotpEnrollmentScreen> createState() => _TotpEnrollmentScreenState();
}

class _TotpEnrollmentScreenState extends State<TotpEnrollmentScreen> {
  final _codeController = TextEditingController();
  TotpEnrollmentData? _enrollment;
  String? _error;
  bool _loading = true;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final enrollment = await context
        .read<SupabaseService>()
        .beginTotpEnrollment();
    if (!mounted) return;
    setState(() {
      _enrollment = enrollment;
      _loading = false;
      _error = enrollment == null ? '認証アプリの登録を開始できませんでした。' : null;
    });
  }

  Future<void> _verify() async {
    final enrollment = _enrollment;
    if (enrollment == null || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final error = await context.read<SupabaseService>().verifyTotpEnrollment(
      factorId: enrollment.factorId,
      code: _codeController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _error = error;
    });
    if (error == null) widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final enrollment = _enrollment;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: widget.allowClose,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('認証アプリを登録'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _loading
                ? const CircularProgressIndicator()
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        '二段階認証を設定します',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Google Authenticator、Microsoft Authenticator、iPhoneの「パスワード」などでQRコードを読み取ってください。',
                        style: TextStyle(color: Colors.white70, height: 1.6),
                      ),
                      if (enrollment != null) ...[
                        const SizedBox(height: 24),
                        Center(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(16),
                            child: QrImageView(
                              data: enrollment.uri,
                              size: 230,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '読み取れない場合の設定キー',
                          style: TextStyle(color: Colors.white70),
                        ),
                        SelectableText(
                          enrollment.secret,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'このQRコードと設定キーは第三者へ送らず、スクリーンショットも共有しないでください。',
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          enableInteractiveSelection: true,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                          ),
                          decoration: InputDecoration(
                            labelText: '認証アプリの6桁コード',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: '認証コードを貼り付け',
                              onPressed: _verifying
                                  ? null
                                  : () => pasteClipboardInto(_codeController),
                              icon: const Icon(Icons.content_paste_outlined),
                            ),
                          ),
                          onSubmitted: (_) => _verify(),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _verifying ? null : _verify,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: const Color(0xFFFF1F1F),
                          ),
                          child: _verifying
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text('登録を完了する'),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      if (enrollment == null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _start,
                          child: const Text('再試行'),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class TotpChallengeScreen extends StatefulWidget {
  const TotpChallengeScreen({
    super.key,
    required this.purpose,
    required this.onCompleted,
  });

  final String purpose;
  final VoidCallback onCompleted;

  @override
  State<TotpChallengeScreen> createState() => _TotpChallengeScreenState();
}

class _TotpChallengeScreenState extends State<TotpChallengeScreen> {
  final _codeController = TextEditingController();
  String? _factorId;
  String? _message;
  TotpVerificationState? _state;
  bool _loading = true;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = context.read<SupabaseService>();
    final factorId = await service.verifiedTotpFactorId();
    final state = await service.fetchTotpVerificationState(
      purpose: widget.purpose,
    );
    if (!mounted) return;
    setState(() {
      _factorId = factorId;
      _state = state;
      _loading = false;
      if (factorId == null) _message = '登録済みの認証アプリが見つかりません。';
    });
  }

  Future<void> _verify() async {
    final factorId = _factorId;
    if (factorId == null || _verifying || _state?.locked == true) return;
    setState(() {
      _verifying = true;
      _message = null;
    });
    final result = await context.read<SupabaseService>().verifyTotpCode(
      purpose: widget.purpose,
      factorId: factorId,
      code: _codeController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _state = result.state;
      _message = result.state.locked ? null : result.error;
    });
    if (result.succeeded) widget.onCompleted();
  }

  Future<void> _recoverLostDevice() async {
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TotpRecoveryPasswordDialog(),
    );
    if (!mounted || password == null) return;
    setState(() {
      _verifying = true;
      _message = null;
    });
    final error = await context
        .read<SupabaseService>()
        .resetOwnTotpWithPrivacyPassword(password);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _message = error;
    });
    if (error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => TotpEnrollmentScreen(
          onCompleted: () {
            Navigator.of(routeContext).pop();
            widget.onCompleted();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final locked = state?.locked == true;
    final isPasswordRecovery = widget.purpose == 'privacy_recovery';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('認証アプリで本人確認'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _loading
              ? const CircularProgressIndicator()
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Icon(
                      Icons.phonelink_lock,
                      color: Colors.white,
                      size: 58,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '認証アプリに表示されている6桁コードを入力してください。',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isPasswordRecovery) ...[
                      const Text(
                        '認証コードを5回誤入力すると、パスワードの再設定は24時間ロックされます。ロック中も他の画面は閲覧できます。',
                        style: TextStyle(color: Colors.white70, height: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        locked
                            ? _lockedMessage(state?.lockedUntil)
                            : 'あと${state?.remainingAttempts ?? 5}回で、24時間ロックされます。',
                        style: TextStyle(
                          color: locked
                              ? Colors.redAccent
                              : Colors.orangeAccent,
                          height: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else
                      const Text(
                        'この確認はログインを保護するためのものです。',
                        style: TextStyle(color: Colors.white70),
                      ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _codeController,
                      enabled: !locked && _factorId != null,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enableInteractiveSelection: true,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      style: const TextStyle(color: Colors.white, fontSize: 24),
                      decoration: InputDecoration(
                        labelText: '6桁コード',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '認証コードを貼り付け',
                          onPressed: locked || _verifying || _factorId == null
                              ? null
                              : () => pasteClipboardInto(_codeController),
                          icon: const Icon(Icons.content_paste_outlined),
                        ),
                      ),
                      onSubmitted: (_) => _verify(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: locked || _verifying ? null : _verify,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: const Color(0xFFFF1F1F),
                      ),
                      child: _verifying
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('本人確認する'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _verifying ? null : _recoverLostDevice,
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('認証端末を紛失した方・QRコードを再取得'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ContactScreen(
                            initialCategory: 'totp_recovery',
                          ),
                        ),
                      ),
                      child: const Text('パスワードも分からない場合は問い合わせる'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _message!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  String _lockedMessage(DateTime? retryAt) => retryAt == null
      ? '上限回数に達しました。24時間後に再度入力してください。'
      : '上限回数に達しました。${formatJapaneseMonthDayTime(retryAt)}（24時間後）以降に再度入力してください。';
}

class TotpManagementScreen extends StatefulWidget {
  const TotpManagementScreen({super.key});

  @override
  State<TotpManagementScreen> createState() => _TotpManagementScreenState();
}

class _TotpManagementScreenState extends State<TotpManagementScreen> {
  bool _loading = true;
  bool _enrolled = false;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final enrolled = await context
        .read<SupabaseService>()
        .hasVerifiedTotpFactor();
    if (!mounted) return;
    setState(() {
      _enrolled = enrolled;
      _loading = false;
    });
  }

  Future<void> _reenroll() async {
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _TotpRecoveryPasswordDialog(),
    );
    if (!mounted || password == null) return;
    setState(() => _processing = true);
    final error = await context
        .read<SupabaseService>()
        .resetOwnTotpWithPrivacyPassword(password);
    if (!mounted) return;
    setState(() => _processing = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => TotpEnrollmentScreen(
          allowClose: false,
          onCompleted: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('認証アプリの管理')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: _loading
              ? const CircularProgressIndicator()
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    ListTile(
                      leading: Icon(
                        _enrolled ? Icons.verified_user : Icons.warning_amber,
                        color: _enrolled ? Colors.green : Colors.orange,
                      ),
                      title: Text(_enrolled ? '二段階認証は有効です' : '二段階認証が未登録です'),
                      subtitle: const Text('認証アプリのQRコードと設定キーは、登録時にだけ表示します。'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _processing ? null : _reenroll,
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(_processing ? '確認中…' : '認証用QRコードを再取得'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '再取得には個人情報変更用パスワードが必要です。再取得すると以前の認証アプリは使えなくなり、操作は監査記録へ保存されます。',
                      style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ContactScreen(
                            initialCategory: 'totp_recovery',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.support_agent),
                      label: const Text('パスワードも分からない場合は問い合わせる'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TotpRecoveryPasswordDialog extends StatefulWidget {
  const _TotpRecoveryPasswordDialog();

  @override
  State<_TotpRecoveryPasswordDialog> createState() =>
      _TotpRecoveryPasswordDialogState();
}

class _TotpRecoveryPasswordDialogState
    extends State<_TotpRecoveryPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('認証アプリを再登録'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('個人情報変更用パスワードを入力してください。以前の認証アプリは無効になります。'),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            enableInteractiveSelection: true,
            decoration: InputDecoration(
              labelText: '個人情報変更用パスワード',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'パスワードを貼り付け',
                    onPressed: () => pasteClipboardInto(_controller),
                    icon: const Icon(Icons.content_paste_outlined),
                  ),
                  IconButton(
                    tooltip: _obscure ? 'パスワードを表示' : 'パスワードを隠す',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('確認して再登録'),
        ),
      ],
    );
  }
}
