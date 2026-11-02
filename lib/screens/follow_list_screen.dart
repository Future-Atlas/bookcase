import 'package:flutter/material.dart';
import '../services/avatar_url_policy.dart';
import 'package:provider/provider.dart';

import '../models/social_models.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';

class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.profileId,
    required this.followers,
    required this.onProfileTap,
  });

  final String profileId;
  final bool followers;
  final ValueChanged<UserProfile> onProfileTap;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  List<UserProfile> _profiles = const [];
  Map<String, FollowRelationshipStatus> _followStatuses = const {};
  final Set<String> _pendingProfileIds = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = Provider.of<SupabaseService>(context, listen: false);
    final profiles = await service.fetchProfileFollowList(
      profileId: widget.profileId,
      followers: widget.followers,
    );
    final followStatuses = await service.fetchCurrentFollowStatuses(
      profiles.map((profile) => profile.id),
    );
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _followStatuses = followStatuses;
      _loading = false;
    });
  }

  Future<void> _toggleFollow(UserProfile profile) async {
    if (!_pendingProfileIds.add(profile.id)) return;

    final previousStatus =
        _followStatuses[profile.id] ?? FollowRelationshipStatus.none;
    final wasFollowing = previousStatus != FollowRelationshipStatus.none;
    final optimisticStatus = wasFollowing
        ? FollowRelationshipStatus.none
        : profile.isPrivate
        ? FollowRelationshipStatus.pending
        : FollowRelationshipStatus.accepted;
    setState(() {
      _followStatuses = Map<String, FollowRelationshipStatus>.from(
        _followStatuses,
      )..[profile.id] = optimisticStatus;
    });

    final service = Provider.of<SupabaseService>(context, listen: false);
    final returnedStatus = wasFollowing
        ? null
        : await service.followProfile(profile.id);
    final success = wasFollowing
        ? await service.unfollowProfile(profile.id)
        : returnedStatus != null;
    _pendingProfileIds.remove(profile.id);
    if (!mounted) return;

    if (!success) {
      setState(() {
        _followStatuses = Map<String, FollowRelationshipStatus>.from(
          _followStatuses,
        )..[profile.id] = previousStatus;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('フォロー設定を変更できませんでした。')));
      return;
    }

    if (returnedStatus != null && returnedStatus != optimisticStatus) {
      setState(() {
        _followStatuses = Map<String, FollowRelationshipStatus>.from(
          _followStatuses,
        )..[profile.id] = returnedStatus;
      });
    } else {
      setState(() {});
    }
  }

  Widget _buildFollowButton(UserProfile profile) {
    final service = Provider.of<SupabaseService>(context, listen: false);
    if (!service.isAuthenticated || profile.id == service.activeProfileId) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (profile.isPrivate) ...[
            const Icon(Icons.lock_outline, size: 18),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right),
        ],
      );
    }

    final status = _followStatuses[profile.id] ?? FollowRelationshipStatus.none;
    final label = switch (status) {
      FollowRelationshipStatus.none => 'フォロー',
      FollowRelationshipStatus.pending => 'リクエスト済み',
      FollowRelationshipStatus.accepted => 'フォロー中',
    };
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isPending = _pendingProfileIds.contains(profile.id);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (profile.isPrivate) ...[
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 6),
        ],
        SizedBox(
          width: 112,
          height: 36,
          child: FilledButton(
            onPressed: isPending ? null : () => _toggleFollow(profile),
            style: status == FollowRelationshipStatus.accepted
                ? FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: isDarkMode
                        ? const Color(0xFFF2F2F2)
                        : Colors.black,
                    foregroundColor: const Color(0xFF00BFFF),
                    disabledBackgroundColor: isDarkMode
                        ? const Color(0xFFF2F2F2)
                        : Colors.black,
                    disabledForegroundColor: const Color(0xFF00BFFF),
                  )
                : FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
            child: Text(label, maxLines: 1),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.followers ? 'フォロワー' : 'フォロー')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
          ? Center(
              child: Text(
                widget.followers ? 'フォロワーはいません。' : 'フォローしているユーザーはいません。',
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _profiles.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final profile = _profiles[index];
                  return ListTile(
                    onTap: () => widget.onProfileTap(profile),
                    leading: CircleAvatar(
                      backgroundImage: profile.avatarUrl.isEmpty
                          ? null
                          : AvatarUrlPolicy.image(profile.avatarUrl),
                      child: profile.avatarUrl.isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(
                      profile.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      profile.userId.isEmpty ? '' : '@${profile.userId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _buildFollowButton(profile),
                  );
                },
              ),
            ),
    );
  }
}
