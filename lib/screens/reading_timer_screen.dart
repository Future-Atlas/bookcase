import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/reading_session.dart';
import '../services/reading_session_service.dart';
import '../widgets/reading_cover_art.dart';

class ReadingTimerScreen extends StatefulWidget {
  const ReadingTimerScreen({
    super.key,
    this.book,
    this.resuming,
    required this.accentColor,
    this.onFinished,
    this.onDefer,
  }) : assert(book != null || resuming != null);

  final Book? book;
  final ReadingSession? resuming;
  final Color accentColor;
  final VoidCallback? onFinished;
  final VoidCallback? onDefer;

  @override
  State<ReadingTimerScreen> createState() => _ReadingTimerScreenState();
}

class _ReadingTimerScreenState extends State<ReadingTimerScreen> {
  final ReadingSessionService _service = ReadingSessionService();
  ReadingSession? _active;
  Timer? _ticker;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _active = widget.resuming;
    if (_active != null) _startTicking();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _active == null) return;
      setState(() {});
      if (_active!.duration().inSeconds >= 24 * 60 * 60 && !_busy) {
        _finish();
      }
    });
  }

  Future<void> _start() async {
    if (_busy || _active != null || widget.book == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final current = await _service.start(widget.book!);
      if (!mounted) return;
      setState(() => _active = current);
      _startTicking();
    } catch (_) {
      // Another tab or a previous browser session may already be recording.
      // Restore that server-side session instead of trapping the user in a
      // repeated start error without a way to stop the running timer.
      ReadingSession? existing;
      try {
        existing = await _service.activeSession();
      } catch (_) {
        // Preserve the original failure semantics if the lookup also fails.
      }
      if (!mounted) return;
      if (existing != null) {
        setState(() {
          _active = existing;
          _error =
              'すでに「${existing!.bookTitle}」を計測中です。'
              'こちらのタイマーを終了すると記録できます。';
        });
        _startTicking();
      } else {
        setState(() => _error = '計測を開始できませんでした。通信環境とログイン状態を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_busy || _active == null) return;
    _ticker?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.finish(_active!.id);
      if (!mounted) return;
      if (widget.onFinished != null) {
        widget.onFinished!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '読書時間を保存できませんでした。通信環境を確認して再度お試しください。');
      _startTicking();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _clock {
    final elapsed = _active?.duration() ?? Duration.zero;
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final session = _active ?? widget.resuming;
    final title = session?.bookTitle ?? widget.book?.title ?? '';
    final book =
        widget.book ??
        Book(
          id: session!.bookId,
          title: session.bookTitle,
          author: '',
          publisher: '',
          pubDate: '',
          isbn: session.bookIsbn,
          coverUrl: session.bookCoverUrl,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('読書タイマー'),
        automaticallyImplyLeading: widget.onDefer == null,
        actions: [
          if (widget.onDefer != null)
            TextButton(onPressed: widget.onDefer, child: const Text('あとで終了する')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ClipOval(
                  child: SizedBox.square(
                    dimension: 112,
                    child: ColoredBox(
                      color: Colors.black12,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: ReadingCoverArt(url: book.coverUrl),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 38),
              Text(
                _clock,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 54,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: widget.accentColor,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : (_active == null ? _start : _finish),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(220, 52),
                  ),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_active == null ? Icons.play_arrow : Icons.stop),
                  label: Text(_active == null ? '読書を開始する' : '計測を終了して記録'),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '1回の計測は最大24時間です。\n'
                '画面を閉じても、計測中の記録はカレンダーから再開できます。',
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
