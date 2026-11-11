import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile_page_color.dart';
import '../models/reading_session.dart';
import '../services/reading_session_service.dart';
import '../services/supabase_service.dart';
import 'reading_timer_screen.dart';

/// Appears only after the existing consent, registration and TOTP gates.
/// An unfinished reading timer is restored automatically after sign-in or
/// a browser reload. No session ID is stored in the browser.
class ReadingTimerResumeGate extends StatefulWidget {
  const ReadingTimerResumeGate({super.key, required this.child});

  final Widget child;

  @override
  State<ReadingTimerResumeGate> createState() => _ReadingTimerResumeGateState();
}

class _ReadingTimerResumeGateState extends State<ReadingTimerResumeGate> {
  String? _checkedUserId;
  Future<ReadingSession?>? _pending;
  bool _deferred = false;

  void _reload() {
    setState(() {
      _deferred = false;
      _pending = ReadingSessionService().activeSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SupabaseService>(
      builder: (context, service, _) {
        final userId = service.isAuthenticated ? service.activeProfileId : '';
        if (userId.isEmpty) {
          // The next login must check again, even for the same account.
          _checkedUserId = null;
          _pending = null;
          _deferred = false;
          return widget.child;
        }

        if (_checkedUserId != userId) {
          _checkedUserId = userId;
          _deferred = false;
          _pending = ReadingSessionService().activeSession();
        }

        if (_deferred) return widget.child;

        return FutureBuilder<ReadingSession?>(
          future: _pending,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('読書タイマーの確認')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('前回の読書タイマーを確認できませんでした。'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('再試行'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _deferred = true),
                          child: const Text('あとで確認する'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final active = snapshot.data;
            if (active == null) return widget.child;

            return ReadingTimerScreen(
              key: ValueKey('restored-reading-timer-${active.id}'),
              resuming: active,
              accentColor: ProfilePageColors.colorFor(
                service.activePageColorKey,
              ),
              // Completion is confirmed by the server before this callback.
              onFinished: () => setState(() {
                _deferred = true;
                _pending = null;
              }),
              // The timer stays active if the user chooses to visit the app.
              onDefer: () => setState(() => _deferred = true),
            );
          },
        );
      },
    );
  }
}
