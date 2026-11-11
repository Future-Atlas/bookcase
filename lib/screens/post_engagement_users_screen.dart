import 'package:flutter/material.dart';
import '../services/avatar_url_policy.dart';
import 'package:provider/provider.dart';

import '../models/social_models.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../services/reading_session_service.dart';
import '../widgets/profile_color_border.dart';

class PostEngagementUsersScreen extends StatefulWidget {
  const PostEngagementUsersScreen({
    super.key,
    this.postId = '',
    this.readingSessionId,
    required this.title,
    required this.onProfileTap,
    this.reaction,
    this.wantToRead = false,
  }) : assert(postId != '' || readingSessionId != null);

  final String postId;
  final String? readingSessionId;
  final String title;
  final PostReactionType? reaction;
  final bool wantToRead;
  final ValueChanged<UserProfile> onProfileTap;

  @override
  State<PostEngagementUsersScreen> createState() =>
      _PostEngagementUsersScreenState();
}

class _PostEngagementUsersScreenState extends State<PostEngagementUsersScreen> {
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
    final profiles = widget.readingSessionId != null && widget.reaction != null
        ? await ReadingSessionService().reactionUsers(
            widget.readingSessionId!, widget.reaction!,
          )
        : await service.fetchPostEngagementUsers(
            postId: widget.postId,
            reaction: widget.reaction,
            wantToRead: widget.wantToRead,
          );
    final statuses = await service.fetchCurrentFollowStatuses(
      profiles.map((profile) => profile.id),
    );
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _followStatuses = statuses;
      _loading = false;
    });
  }

  Future<void> _toggleFollow(UserProfile profile) async {
    if (!_pendingProfileIds.add(profile.id)) return;
    final previous =
        _followStatuses[profile.id] ?? FollowRelationshipStatus.none;
    final wasFollowing = previous != FollowRelationshipStatus.none;
    final optimistic = wasFollowing
        ? FollowRelationshipStatus.none
        : profile.isPrivate
        ? FollowRelationshipStatus.pending
        : FollowRelationshipStatus.accepted;
    setState(() {
      _followStatuses = Map<String, FollowRelationshipStatus>.from(
        _followStatuses,
      )..[profile.id] = optimistic;
    });

    final service = Provider.of<SupabaseService>(context, listen: false);
    final returned = wasFollowing
        ? null
        : await service.followProfile(profile.id);
    final success = wasFollowing
        ? await service.unfollowProfile(profile.id)
        : returned != null;
    _pendingProfileIds.remove(profile.id);
    if (!mounted) return;
    if (!success) {
      setState(() {
        _followStatuses = Map<String, FollowRelationshipStatus>.from(
          _followStatuses,
        )..[profile.id] = previous;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('フォロー設定を変更できませんでした。')));
      return;
    }
    setState(() {
      if (returned != null) {
        _followStatuses = Map<String, FollowRelationshipStatus>.from(
          _followStatuses,
        )..[profile.id] = returned;
      }
    });
  }

  Widget _trailing(UserProfile profile) {
    final service = Provider.of<SupabaseService>(context, listen: false);
    if (!service.isAuthenticated || profile.id == service.activeProfileId) {
      return const Icon(Icons.chevron_right);
    }
    final status = _followStatuses[profile.id] ?? FollowRelationshipStatus.none;
    final label = switch (status) {
      FollowRelationshipStatus.none => 'フォロー',
      FollowRelationshipStatus.pending => 'リクエスト済み',
      FollowRelationshipStatus.accepted => 'フォロー中',
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 112,
      height: 36,
      child: FilledButton(
        onPressed: _pendingProfileIds.contains(profile.id)
            ? null
            : () => _toggleFollow(profile),
        style: status == FollowRelationshipStatus.accepted
            ? FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: dark ? const Color(0xFFF2F2F2) : Colors.black,
                foregroundColor: const Color(0xFF00BFFF),
              )
            : FilledButton.styleFrom(padding: EdgeInsets.zero),
        child: Text(label, maxLines: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
          ? const Center(child: Text('このリアクションをしたユーザーはいません。'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: _profiles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final profile = _profiles[index];
                  return ProfileColorBorder(
                    pageColorKey: profile.pageColorKey,
                    child: ListTile(
                      onTap: () => widget.onProfileTap(profile),
                      leading: CircleAvatar(
                        backgroundImage: profile.avatarUrl.isEmpty
                            ? null
                            : AvatarUrlPolicy.image(profile.avatarUrl),
                        child: profile.avatarUrl.isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(profile.username),
                      subtitle: Text(
                        profile.userId.isEmpty ? '' : '@${profile.userId}',
                      ),
                      trailing: _trailing(profile),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
