import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/book.dart';
import '../models/reading_session.dart';

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

  /// Fetch every session overlapping a month, paging beyond PostgREST's
  /// default row limit. A session is capped at 24h, so one day of lookback
  /// is enough to include overnight reading on the first day of the month.
  Future<List<ReadingSession>> loadMonth(DateTime month) async {
    if (_currentId.isEmpty) return [];
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
          .eq('profile_id', _currentId)
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
