import 'package:flutter/material.dart';

import '../utils/text_field_clipboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Optional authenticator-app MFA setup and step-up verification.
/// Enrollment secrets are displayed only in the local view. They are never
/// written to app databases, logs, analytics or server-rendered HTML.
class MfaSettingsScreen extends StatefulWidget {
  const MfaSettingsScreen({super.key});

  @override
  State<MfaSettingsScreen> createState() => _MfaSettingsScreenState();
}

class _MfaSettingsScreenState extends State<MfaSettingsScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  bool _hasFactor = false;
  bool _aal2 = false;
  String? _factorId;
  String? _pendingSecret;
  String? _message;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_client.auth.currentUser == null) return;
    setState(() => _busy = true);
    try {
      final factors = await _client.auth.mfa.listFactors();
      final levels = await _client.auth.mfa.getAuthenticatorAssuranceLevel();
      String? verifiedId;
      for (final factor in factors.totp) {
        final status = factor.status.toString().toLowerCase();
        if (status == 'verified' || status.endsWith('.verified')) {
          verifiedId = factor.id;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _factorId = verifiedId;
        _hasFactor = verifiedId != null;
        _aal2 = levels.currentLevel.toString().toLowerCase().endsWith('aal2');
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'MFA設定を取得できませんでした。通信状態をご確認ください。';
      });
    }
  }

  Future<void> _enroll() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      final enrollment = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        friendlyName: 'Sharemarium 認証アプリ',
      );
      if (!mounted) return;
      setState(() {
        _factorId = enrollment.id;
        _pendingSecret = enrollment.totp?.secret;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '登録を開始できませんでした。再度お試しください。';
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (_busy || _factorId == null) return;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      setState(() => _message = '認証アプリに表示された6桁のコードを入力してください。');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      await _client.auth.mfa.challengeAndVerify(
        factorId: _factorId!,
        code: code,
      );
      _codeController.clear();
      if (!mounted) return;
      setState(() {
        _pendingSecret = null;
        _aal2 = true;
        _hasFactor = true;
        _busy = false;
        _message = '二段階認証を確認しました。管理者操作にも利用できます。';
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '認証コードを確認できませんでした。端末の時刻もご確認ください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('二段階認証（MFA）')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _aal2 ? 'このセッションは二段階認証済みです。'
                    : _hasFactor
                    ? '認証アプリが登録済みです。現在のセッションでは認証コードを入力してください。'
                    : '認証アプリを登録すると、パスワードなどに加えて本人確認ができます。',
              ),
              const SizedBox(height: 18),
              if (!_hasFactor && _pendingSecret == null)
                FilledButton.icon(
                  onPressed: _busy ? null : _enroll,
                  icon: const Icon(Icons.security),
                  label: const Text('認証アプリを登録'),
                ),
              if (_pendingSecret != null) ...[
                const Text('認証アプリに以下の秘密鍵を手動で登録してください。'
                    'この鍵を他人に見せたり共有したりしないでください。'),
                const SizedBox(height: 12),
                SelectableText(_pendingSecret!,
                    style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 18),
              ],
              if (_factorId != null && !_aal2) ...[
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enableInteractiveSelection: true,
                  decoration: InputDecoration(
                    labelText: '認証アプリの6桁コード',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '認証コードを貼り付け',
                      onPressed: _busy ? null : () => pasteClipboardInto(_codeController),
                      icon: const Icon(Icons.content_paste_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _verify,
                  child: const Text('コードを検証して続ける'),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!),
              ],
              if (_busy) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              const Text('端末を紛失した場合に備え、複数の認証アプリ・端末を用意してください。'
                  '管理者操作には認証済みセッションが必要です。'),
            ],
          ),
        ),
      ),
    );
  }
}
