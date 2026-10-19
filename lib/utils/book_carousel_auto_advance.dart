import 'dart:async';

typedef AutoAdvanceCallback = void Function();

/// Controls automatic movement for a home-screen book carousel.
///
/// A user interaction pauses movement for [resumeDelay]. Opening a book detail
/// pauses the countdown entirely; when the detail closes, a fresh idle period
/// starts so time spent reading the dialog is not counted.
class BookCarouselAutoAdvance {
  BookCarouselAutoAdvance({
    required this.onAdvance,
    this.advanceInterval = const Duration(milliseconds: 1500),
    this.resumeDelay = const Duration(seconds: 10),
  });

  final AutoAdvanceCallback onAdvance;
  final Duration advanceInterval;
  final Duration resumeDelay;

  Timer? _advanceTimer;
  Timer? _resumeTimer;
  bool _detailOpen = false;
  bool _disposed = false;
  bool get isPaused =>
      _detailOpen || _resumeTimer?.isActive == true || _disposed;

  void start() {
    if (_disposed || _detailOpen) return;
    _startAdvanceTimer();
  }

  void registerUserInteraction() {
    if (_disposed) return;
    _cancelTimers();
    if (_detailOpen) return;
    _resumeTimer = Timer(resumeDelay, _startAdvanceTimer);
  }

  void pauseForBookDetail() {
    if (_disposed) return;
    _detailOpen = true;
    _cancelTimers();
  }

  void resumeAfterBookDetail() {
    if (_disposed) return;
    _detailOpen = false;
    registerUserInteraction();
  }

  void dispose() {
    _disposed = true;
    _cancelTimers();
  }

  void _startAdvanceTimer() {
    if (_disposed || _detailOpen) return;
    _advanceTimer?.cancel();
    _advanceTimer = Timer.periodic(advanceInterval, (_) => onAdvance());
  }

  void _cancelTimers() {
    _advanceTimer?.cancel();
    _resumeTimer?.cancel();
    _advanceTimer = null;
    _resumeTimer = null;
  }
}
