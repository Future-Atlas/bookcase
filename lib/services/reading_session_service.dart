import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/book.dart';
import '../models/reading_session.dart';
import '../models/social_models.dart';

/// No local timestamp can create or modify a stored reading record.
/// All writes go through authenticated, server-clock RPCs.
class ReadingSessionService {
  ReadingSessionService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _currentId => _client.auth.currentUser?.id ?? '';

  Future<ReadingSession?> activeSession() async {
    if (_currentId.isEmpty) return null;
    final row = await _client
        .from('reading_sessions')
        .select()
        .eq('profile_id', _currentId)
        .isFilter('ended_at', null)
        .maybeSingle();
    return row == null ? null : ReadingSession.fromJson(row);
  }

  Future<ReadingSession> start(Book book) async {
    if (_currentId.isEmpty) throw StateError('ログインが必要です。');
    final sessionId = await _client.rpc(
      'start_reading_session',
      params: {
        'p_book_id': book.id,
        'p_book_title': book.title,
        'p_book_cover_url': book.coverUrl,
        'p_book_isbn': book.isbn,
        'p_book_cover_source': book.coverSource,
      },
    );
    final row = await _client
        .from('reading_sessions')
        .select()
        .eq('id', sessionId.toString())
        .eq('profile_id', _currentId)
        .single();
    return ReadingSession.fromJson(row);
  }

  Future<ReadingSession> finish(String sessionId) async {
    if (_currentId.isEmpty) throw StateError('ログインが必要です。');
    final row = await _client.rpc(
      'finish_reading_session',
      params: {'p_session_id': sessionId},
    );
    return ReadingSession.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Owner or an accepted follower not excluded by the owner.
  Future<bool> canViewCalendar(String ownerId) async {
    if (_currentId.isEmpty || ownerId.isEmpty) return false;
    return await _client.rpc(
      'can_view_reading_calendar',
      params: {'target_owner': ownerId},
    ) == true;
  }

  /// The only editable visibility entries are accepted followers.
  Future<Set<String>> hiddenFollowerIds() async {
    if (_currentId.isEmpty) return {};
    final rows = await _client
        .from('reading_calendar_hidden_followers')
        .select('follower_id')
        .eq('owner_id', _currentId);
    return rows.map((row) => row['follower_id'].toString()).toSet();
  }

  Future<void> setFollowerHidden(String followerId, bool hidden) async {
    if (_currentId.isEmpty) throw StateError('ログインが必要です。');
    await _client.rpc('set_reading_calendar_follower_hidden', params: {
      'p_follower_id': followerId,
      'p_hidden': hidden,
    });
  }

  Future<Map<String, ReadingReactionSummary>> reactionSummaries(
    List<ReadingSession> sessions,
  ) async {
    if (_currentId.isEmpty || sessions.isEmpty) return {};
    final summaries = <String, ReadingReactionSummary>{};
    const pageSize = 500;
    final ids = sessions.map((session) => session.id).toSet().toList();
    // Keep requests small even if the user has an exceptionally large month.
    for (var from = 0; from < ids.length; from += 100) {
      final subset = ids.skip(from).take(100).toList(growable: false);
      var offset = 0;
      while (true) {
        final rows = await _client
            .from('reading_session_reactions')
            .select('reading_session_id,profile_id,reaction_type')
            .inFilter('reading_session_id', subset)
            .range(offset, offset + pageSize - 1);
        for (final row in rows) {
          final sessionId = row['reading_session_id']?.toString() ?? '';
          final type = PostReactionType.fromDatabase(
            row['reaction_type']?.toString(),
          );
          if (sessionId.isEmpty || type == null) continue;
          final current = summaries[sessionId] ?? const ReadingReactionSummary();
          final next = Map<PostReactionType, int>.from(current.counts);
          next[type] = (next[type] ?? 0) + 1;
          summaries[sessionId] = ReadingReactionSummary(
            counts: next,
            selected: row['profile_id']?.toString() == _currentId
                ? type
                : current.selected,
          );
        }
        if (rows.length < pageSize) break;
        offset += pageSize;
      }
    }
    return summaries;
  }

  /// The same three reactions and toggle behavior as book reviews.
  Future<void> toggleReaction(
    String sessionId,
    PostReactionType type,
    PostReactionType? previous,
  ) async {
    if (_currentId.isEmpty) throw StateError('ログインが必要です。');
    if (previous == type) {
      await _client.from('reading_session_reactions').delete()
          .eq('reading_session_id', sessionId).eq('profile_id', _currentId);
    } else {
      await _client.from('reading_session_reactions').upsert({
        'reading_session_id': sessionId,
        'profile_id': _currentId,
        'reaction_type': type.databaseValue,
      });
    }
  }

  /// Fetch every session overlapping a month, paging beyond PostgREST's
  /// default row limit. A session is capped at 24h, so one day of lookback
  /// is enough to include overnight reading on the first day of the month.
  Future<List<ReadingSession>> loadMonth(DateTime month, {String? profileId}) async {
    final owner = profileId ?? _currentId;
    if (_currentId.isEmpty || owner.isEmpty) return [];
    final firstDay = DateTime(month.year, month.month, 1);
    final from = firstDay.subtract(const Duration(days: 1));
    final until = DateTime(month.year, month.month + 1, 1);
    const pageSize = 500;
    var offset = 0;
    final all = <ReadingSession>[];

    while (true) {
      final rows = await _client
          .from('reading_sessions')
          .select()
          .eq('profile_id', owner)
          .gte('started_at', from.toUtc().toIso8601String())
          .lt('started_at', until.toUtc().toIso8601String())
          .order('started_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      all.addAll(rows.map((row) => ReadingSession.fromJson(row)));
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }
}

class ReadingReactionSummary {
  const ReadingReactionSummary({
    this.counts = const {},
    this.selected,
  });

  final Map<PostReactionType, int> counts;
  final PostReactionType? selected;
}
