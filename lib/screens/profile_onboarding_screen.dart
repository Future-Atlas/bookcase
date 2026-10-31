import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../utils/public_user_id.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

enum _OnboardingRequirement {
  complete,
  profile,
  privacyPassword,
  guardianConsent,
}

class ProfileOnboardingGate extends StatefulWidget {
  const ProfileOnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<ProfileOnboardingGate> createState() => _ProfileOnboardingGateState();
}

class _ProfileOnboardingGateState extends State<ProfileOnboardingGate> {
  String? _checkedUserId;
  Future<_OnboardingRequirement>? _future;

  Future<_OnboardingRequirement> _check(SupabaseService service) async {
    final hasProfile = await service.hasCompletedRegistration(
      forceRefresh: true,
    );
    if (!hasProfile) return _OnboardingRequirement.profile;
    if (!await service.hasPrivacyPassword()) {
      return _OnboardingRequirement.privacyPassword;
    }
    return await service.requiresGuardianConsent()
        ? _OnboardingRequirement.guardianConsent
        : _OnboardingRequirement.complete;
  }

  void _refresh(SupabaseService service) {
    setState(() => _future = _check(service));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SupabaseService>(
      builder: (context, service, _) {
        if (!service.isAuthenticated) {
          _checkedUserId = null;
          _future = null;
          return widget.child;
        }
        if (_checkedUserId != service.activeProfileId || _future == null) {
          _checkedUserId = service.activeProfileId;
          _future = _check(service);
        }
        return FutureBuilder<_OnboardingRequirement>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                backgroundColor: Colors.black,
                body: Center(child: CircularProgressIndicator()),
              );
            }
            switch (snapshot.data!) {
              case _OnboardingRequirement.complete:
                return widget.child;
              case _OnboardingRequirement.privacyPassword:
                return PrivacyPasswordSetupScreen(
                  onCompleted: () => _refresh(service),
                );
              case _OnboardingRequirement.profile:
                return ProfileOnboardingScreen(
                  onCompleted: () => _refresh(service),
                );
              case _OnboardingRequirement.guardianConsent:
                return GuardianConsentScreen(
                  onCompleted: () => _refresh(service),
                );
            }
          },
        );
      },
    );
  }
}

class GuardianConsentScreen extends StatefulWidget {
  const GuardianConsentScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<GuardianConsentScreen> createState() => _GuardianConsentScreenState();
}

class _GuardianConsentScreenState extends State<GuardianConsentScreen> {
  bool _declared = false;
  bool _saving = false;

  Future<void> _save() async {
    if (!_declared) return;
    setState(() => _saving = true);
    final error = await Provider.of<SupabaseService>(
      context,
      listen: false,
    ).declareGuardianConsent();
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('保護者の同意確認'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  '18歳未満の方は、保護者（法定代理人）の同意が必要です。',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TermsScreen()),
                      ),
                      child: const Text('利用規約を確認'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      ),
                      child: const Text('プライバシーポリシーを確認'),
                    ),
                  ],
                ),
                CheckboxListTile(
                  value: _declared,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _declared = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFFF1F1F),
                  checkColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    '保護者に両文書を確認してもらい、本サービスの利用について同意を得ています。',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving || !_declared ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1F1F),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(_saving ? '保存中...' : '確認して続ける'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PrivacyPasswordSetupScreen extends StatefulWidget {
  const PrivacyPasswordSetupScreen({
    super.key,
    required this.onCompleted,
    this.isRecovery = false,
  });

  final VoidCallback onCompleted;
  /// Reuse the original first-time password setup page for a verified reset.
  final bool isRecovery;

  @override
  State<PrivacyPasswordSetupScreen> createState() =>
      _PrivacyPasswordSetupScreenState();
}

class _PrivacyPasswordSetupScreenState
    extends State<PrivacyPasswordSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscurePassword = true;
  bool _saving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final service = Provider.of<SupabaseService>(context, listen: false);
    final error = widget.isRecovery
        ? await service.resetPrivacyPasswordAfterReauthentication(
            _passwordController.text,
          )
        : await service.initializePrivacyPassword(_passwordController.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (widget.isRecovery) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('パスワードを再設定しました。')),
      );
    }
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('セキュリティ設定'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.isRecovery
                      ? '新しいパスワードを設定'
                      : '個人情報変更用パスワードを設定してください',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.isRecovery
                      ? 'GoogleまたはXでの本人確認後、15分以内に新しい個人情報変更用パスワードを設定してください。ログイン用パスワードとは別です。'
                      : 'ログインには使用しません。プライバシー設定を開くときに使用します。',
                  style: const TextStyle(color: Colors.white70, height: 1.6),
                ),
                const SizedBox(height: 24),
                _PasswordField(
                  controller: _passwordController,
                  label: widget.isRecovery ? '新しいパスワード' : 'パスワード',
                  obscureText: _obscurePassword,
                  onToggleVisibility: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  validator: validatePrivacyPassword,
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  controller: _confirmationController,
                  label: widget.isRecovery
                      ? '新しいパスワード（確認）'
                      : 'パスワード（確認）',
                  obscureText: _obscurePassword,
                  onToggleVisibility: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  validator: (value) => value != _passwordController.text
                      ? 'パスワードが一致しません。'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1F1F),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(widget.isRecovery ? '再設定する' : '設定する'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  final _personalFormKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();
  final _familyNameController = TextEditingController();
  final _givenNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  final _usernameController = TextEditingController();
  final _userIdController = TextEditingController();
  DateTime? _birthDate;
  String _gender = 'undisclosed';
  int _step = 0;
  bool _isSaving = false;
  bool _didPrefill = false;
  bool _obscurePassword = true;
  bool _guardianConsentDeclared = false;
  String? _userIdError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrefill) return;
    _didPrefill = true;
    final metadata = Provider.of<SupabaseService>(
      context,
      listen: false,
    ).currentUser?.userMetadata;
    final familyName = metadata?['family_name'];
    final givenName = metadata?['given_name'];
    if (familyName is String) _familyNameController.text = familyName.trim();
    if (givenName is String) _givenNameController.text = givenName.trim();
    final username = metadata?['user_name'] ?? metadata?['preferred_username'];
    if (username is String) _usernameController.text = username.trim();
  }

  @override
  void dispose() {
    for (final controller in [
      _familyNameController,
      _givenNameController,
      _phoneController,
      _passwordController,
      _passwordConfirmationController,
      _usernameController,
      _userIdController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: '生年月日を選択',
    );
    if (selected != null && mounted) setState(() => _birthDate = selected);
  }

  void _continue() {
    if (!_personalFormKey.currentState!.validate()) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('生年月日を選択してください。')));
      return;
    }
    if (_isMinor(_birthDate!) && !_guardianConsentDeclared) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('18歳未満の方は、保護者の同意を確認してください。')),
      );
      return;
    }
    setState(() => _step = 1);
  }

  bool _isMinor(DateTime birthDate) {
    final now = DateTime.now();
    final eighteenthBirthday = DateTime(
      birthDate.year + 18,
      birthDate.month,
      birthDate.day,
    );
    return now.isBefore(eighteenthBirthday);
  }

  Future<void> _complete() async {
    setState(() => _userIdError = null);
    if (!_profileFormKey.currentState!.validate() || _birthDate == null) return;
    setState(() => _isSaving = true);
    final service = Provider.of<SupabaseService>(context, listen: false);
    final userId = normalizePublicUserId(_userIdController.text);
    if (!await service.isPublicUserIdAvailable(userId)) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _userIdError = '既に使われているユーザーIDのため、使用できません。他のIDを使用してください。';
      });
      return;
    }
    final error = await service.completeRegistration(
      familyName: _familyNameController.text,
      givenName: _givenNameController.text,
      gender: _gender,
      birthDate: _birthDate!,
      phoneNumber: _phoneController.text,
      username: _usernameController.text,
      userId: userId,
      privacyPassword: _passwordController.text,
      guardianConsentDeclared: _guardianConsentDeclared,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('利用登録'),
        actions: [
          TextButton(
            onPressed: _isSaving
                ? null
                : () => Provider.of<SupabaseService>(
                    context,
                    listen: false,
                  ).signOut(),
            child: const Text('ログアウト'),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                LinearProgressIndicator(
                  value: _step == 0 ? 0.5 : 1,
                  minHeight: 6,
                  color: const Color(0xFFFF1F1F),
                  backgroundColor: Colors.white24,
                ),
                const SizedBox(height: 28),
                _step == 0 ? _personalStep() : _profileStep(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _personalStep() {
    return Form(
      key: _personalFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '基本情報を入力してください',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '氏名・性別・生年月日・電話番号・パスワードは公開されません。',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          const Text(
            '氏名と生年月日は登録後にご自身で変更できません。入力内容を確認し、訂正が必要な場合はお問い合わせください。',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 22),
          TextFormField(
            controller: _familyNameController,
            style: const TextStyle(color: Colors.white),
            maxLength: 50,
            decoration: _decoration('姓（Family name）'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? '姓を入力してください。' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _givenNameController,
            style: const TextStyle(color: Colors.white),
            maxLength: 50,
            decoration: _decoration('名（Given name）'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? '名を入力してください。' : null,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            dropdownColor: const Color(0xFF202020),
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('性別（任意）'),
            items: const [
              DropdownMenuItem(value: 'female', child: Text('女性')),
              DropdownMenuItem(value: 'male', child: Text('男性')),
              DropdownMenuItem(value: 'undisclosed', child: Text('無回答')),
            ],
            onChanged: (value) =>
                setState(() => _gender = value ?? 'undisclosed'),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _selectBirthDate,
            child: InputDecorator(
              decoration: _decoration('生年月日'),
              child: Text(
                _birthDate == null
                    ? '選択してください'
                    : '${_birthDate!.year}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: _birthDate == null ? Colors.white54 : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_birthDate != null && _isMinor(_birthDate!)) ...[
            CheckboxListTile(
              value: _guardianConsentDeclared,
              onChanged: (value) =>
                  setState(() => _guardianConsentDeclared = value ?? false),
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFFFF1F1F),
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                '保護者（法定代理人）に利用規約とプライバシーポリシーを確認してもらい、同意を得ています。',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextFormField(
            controller: _phoneController,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            decoration: _decoration('電話番号'),
            validator: (value) {
              final normalized = (value ?? '').replaceAll(
                RegExp(r'[^0-9+]'),
                '',
              );
              return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)
                  ? null
                  : '有効な電話番号を入力してください。';
            },
          ),
          const SizedBox(height: 18),
          _PasswordField(
            controller: _passwordController,
            label: '個人情報変更用パスワード',
            obscureText: _obscurePassword,
            onToggleVisibility: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            validator: validatePrivacyPassword,
          ),
          const SizedBox(height: 14),
          _PasswordField(
            controller: _passwordConfirmationController,
            label: 'パスワード（確認）',
            obscureText: _obscurePassword,
            onToggleVisibility: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            validator: (value) =>
                value != _passwordController.text ? 'パスワードが一致しません。' : null,
          ),
          const SizedBox(height: 10),
          const Text(
            '大文字・小文字・数字を含む8〜20文字。ログインには使用しません。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _continue,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF1F1F),
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('次へ'),
          ),
        ],
      ),
    );
  }

  Widget _profileStep() {
    return Form(
      key: _profileFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '公開プロフィールを設定してください',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ユーザー名はいつでも変更できます。\nユーザーIDの変更は出来ません。',
            style: TextStyle(color: Colors.white70, height: 1.6),
          ),
          const SizedBox(height: 22),
          TextFormField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            maxLength: 30,
            decoration: _decoration('ユーザー名'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'ユーザー名を入力してください。' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _userIdController,
            style: const TextStyle(color: Colors.white),
            maxLength: 20,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: const [LowerCasePublicUserIdFormatter()],
            onChanged: (_) {
              if (_userIdError != null) setState(() => _userIdError = null);
            },
            decoration: _decoration(
              'ユーザーID',
            ).copyWith(prefixText: '@', errorText: _userIdError),
            validator: validatePublicUserId,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => setState(() => _step = 0),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('戻る'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isSaving ? null : _complete,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1F1F),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('登録を完了する'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white70),
    counterStyle: const TextStyle(color: Colors.white54),
    prefixStyle: const TextStyle(color: Colors.white),
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white38),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFFF1F1F), width: 2),
    ),
    errorBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.redAccent),
    ),
  );
}

String? validatePrivacyPassword(String? value) {
  final password = value ?? '';
  if (password.length < 8 || password.length > 20) {
    return '8文字以上20文字以下にしてください。';
  }
  if (!RegExp(r'[a-z]').hasMatch(password) ||
      !RegExp(r'[A-Z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password)) {
    return '大文字・小文字・数字をすべて含めてください。';
  }
  return null;
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.onToggleVisibility,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enableSuggestions: false,
      autocorrect: false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white38),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFFF1F1F), width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        suffixIcon: IconButton(
          tooltip: obscureText ? 'パスワードを表示' : 'パスワードを隠す',
          onPressed: onToggleVisibility,
          icon: Icon(
            obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.white70,
          ),
        ),
      ),
      validator: validator,
    );
  }
}
