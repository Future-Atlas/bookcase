import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../services/avatar_url_policy.dart';
import '../services/reading_session_service.dart';
import '../services/supabase_service.dart';

/// The owner selects accepted followers who should not see or receive
/// notifications about their reading activity.
class ReadingCalendarVisibilityScreen extends StatefulWidget {
  const ReadingCalendarVisibilityScreen({super.key});

  @override
  State<ReadingCalendarVisibilityScreen> createState() =>
      _ReadingCalendarVisibilityScreenState();
}

class _ReadingCalendarVisibilityScreenState
    extends State<ReadingCalendarVisibilityScreen> {
  final ReadingSessionService _readingService = ReadingSessionService();
  List<UserProfile> _followers = const [];
  Set<String> _hiddenIds = {};
  final Set<String> _savingIds = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = Provider.of<SupabaseService>(context, listen: false);
    try {
      final followers = await service.fetchProfileFollowList(
        profileId: service.activeProfileId,
        followers: true,
      );
      final hidden = await _readingService.hiddenFollowerIds();
      if (!mounted) return;
      setState(() {
        _followers = followers;
        _hiddenIds = hidden;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '公開設定を読み込めませんでした。';
        _loading = false;
      });
    }
  }

  Future<void> _setHidden(UserProfile profile, bool hidden) async {
    if (!_savingIds.add(profile.id)) return;
    setState(() {});
    try {
      await _readingService.setFollowerHidden(profile.id, hidden);
      if (!mounted) return;
      setState(() {
        if (hidden) {
          _hiddenIds.add(profile.id);
        } else {
          _hiddenIds.remove(profile.id);
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('公開設定を保存できませんでした。')),
      );
    } finally {
      _savingIds.remove(profile.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('読書カレンダーを表示しない人')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'フォロワーの中から読書カレンダーを非公開にする人を選べます。'
              '選択した相手には読書記録が表示されず、更新通知も届きません。',
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_error!),
              )
            else if (_followers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Center(child: Text('現在フォロワーはいません。')),
              )
            else
              for (final follower in _followers)
                SwitchListTile(
                  key: ValueKey('calendar-hide-${follower.id}'),
                  value: _hiddenIds.contains(follower.id),
                  onChanged: _savingIds.contains(follower.id)
                      ? null
                      : (value) => _setHidden(follower, value),
                  secondary: CircleAvatar(
                    backgroundImage: follower.avatarUrl.isNotEmpty
                        ? AvatarUrlPolicy.image(follower.avatarUrl)
                        : null,
                    child: follower.avatarUrl.isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(follower.username),
                  subtitle: Text('@${follower.userId}'),
                ),
          ],
        ),
      ),
    );
  }
}
