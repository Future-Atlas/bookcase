import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';

class PrivateAccountAdminPanel extends StatefulWidget {
  const PrivateAccountAdminPanel({super.key});

  @override
  State<PrivateAccountAdminPanel> createState() =>
      _PrivateAccountAdminPanelState();
}

class _PrivateAccountAdminPanelState extends State<PrivateAccountAdminPanel> {
  final _formKey = GlobalKey<FormState>();
  final _targetController = TextEditingController();
  final _referenceController = TextEditingController();
  final _reasonController = TextEditingController();
  final _passwordController = TextEditingController();
  final _familyNameController = TextEditingController();
  final _givenNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  DateTime? _birthDate;
  String _gender = 'undisclosed';
  String? _loadedProfileId;
  bool _processing = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _targetController.dispose();
    _referenceController.dispose();
    _reasonController.dispose();
    _passwordController.dispose();
    _familyNameController.dispose();
    _givenNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _clearSensitiveData() {
    setState(() {
      _passwordController.clear();
      _familyNameController.clear();
      _givenNameController.clear();
      _phoneController.clear();
      _emailController.clear();
      _birthDate = null;
      _gender = 'undisclosed';
      _loadedProfileId = null;
    });
  }

  Future<void> _read() async {
    if (!_validateRequest()) return;
    setState(() => _processing = true);
    final result = await context
        .read<SupabaseService>()
        .adminReadPrivateAccountDetails(
          targetIdentifier: _targetController.text,
          adminPassword: _passwordController.text,
          reason: _reasonController.text,
          requestReference: _referenceController.text,
        );
    if (!mounted) return;
    setState(() => _processing = false);
    _passwordController.clear();
    if (result == null) {
      _showMessage('閲覧できませんでした。管理者権限、追加パスワード、入力内容を確認してください。');
      return;
    }
    setState(() {
      _loadedProfileId = result['profile_id']?.toString();
      _familyNameController.text = result['family_name']?.toString() ?? '';
      _givenNameController.text = result['given_name']?.toString() ?? '';
      _phoneController.text = result['phone_number']?.toString() ?? '';
      _emailController.text = result['email']?.toString() ?? '';
      _birthDate = DateTime.tryParse(result['birth_date']?.toString() ?? '');
      final gender = result['gender']?.toString();
      _gender = const {'female', 'male', 'undisclosed'}.contains(gender)
          ? gender!
          : 'undisclosed';
    });
    _showMessage('閲覧理由と担当者を監査記録へ保存しました。');
  }

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (selected != null && mounted) setState(() => _birthDate = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        !_validateRequest() ||
        _loadedProfileId == null ||
        _birthDate == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('個人情報を訂正しますか？'),
        content: const Text(
          '氏名・生年月日・電話番号・性別の変更内容、担当管理者、理由、受付番号、日時が監査対象になります。'
          'メールアドレスは変更されません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('監査記録を残して訂正'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _processing = true);
    final changed = await context
        .read<SupabaseService>()
        .adminUpdatePrivateAccountDetails(
          targetIdentifier: _loadedProfileId!,
          adminPassword: _passwordController.text,
          reason: _reasonController.text,
          requestReference: _referenceController.text,
          familyName: _familyNameController.text,
          givenName: _givenNameController.text,
          birthDate: _birthDate!,
          phoneNumber: _phoneController.text,
          gender: _gender,
        );
    if (!mounted) return;
    setState(() => _processing = false);
    _passwordController.clear();
    if (changed == null) {
      _showMessage('訂正できませんでした。追加パスワードと入力内容を確認してください。');
      return;
    }
    _showMessage('訂正しました。変更項目と操作理由を監査記録へ保存しました。');
  }

  bool _validateRequest() {
    if (_targetController.text.trim().isEmpty ||
        _referenceController.text.trim().isEmpty ||
        _reasonController.text.trim().length < 10 ||
        _passwordController.text.isEmpty) {
      _showMessage('対象、受付番号、10文字以上の理由、管理者追加パスワードを入力してください。');
      return false;
    }
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? '入力してください。' : null;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: ExpansionTile(
        leading: const Icon(Icons.policy_outlined),
        title: const Text('個人情報対応（全操作を監査）'),
        subtitle: const Text('問い合わせ・適法な開示請求・訂正対応時のみ使用'),
        onExpansionChanged: (expanded) {
          if (!expanded && _loadedProfileId != null) _clearSensitiveData();
        },
        children: [
          Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '対象情報は通常の管理画面からは取得できません。閲覧にも管理者権限、個人情報変更用パスワード、理由、受付番号が必要です。',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _targetController,
                    decoration: const InputDecoration(
                      labelText: '対象の公開ユーザーID又はUUID',
                      border: OutlineInputBorder(),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _referenceController,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: '問い合わせ・事件・受付番号',
                      border: OutlineInputBorder(),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reasonController,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '閲覧・訂正理由（10文字以上）',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 10
                        ? '10文字以上で入力してください。'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '管理者追加パスワード',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _processing ? null : _read,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('理由を記録して閲覧'),
                  ),
                  if (_loadedProfileId != null) ...[
                    const Divider(height: 32),
                    TextFormField(
                      controller: _familyNameController,
                      decoration: const InputDecoration(
                        labelText: '姓（Family name）',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _givenNameController,
                      decoration: const InputDecoration(
                        labelText: '名（Given name）',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('生年月日'),
                      subtitle: Text(
                        _birthDate == null
                            ? '未登録'
                            : '${_birthDate!.year}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: _selectBirthDate,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: '電話番号',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_gender),
                      initialValue: _gender,
                      decoration: const InputDecoration(
                        labelText: '性別（任意）',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'female', child: Text('女性')),
                        DropdownMenuItem(value: 'male', child: Text('男性')),
                        DropdownMenuItem(
                          value: 'undisclosed',
                          child: Text('無回答'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _gender = value ?? 'undisclosed'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'メールアドレス（変更不可）',
                        helperText: '認証サービスで管理され、運営画面からは変更しません。',
                        suffixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _processing ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_processing ? '処理中…' : '監査記録を残して訂正'),
                    ),
                    TextButton(
                      onPressed: _processing ? null : _clearSensitiveData,
                      child: const Text('表示した個人情報を閉じる'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
