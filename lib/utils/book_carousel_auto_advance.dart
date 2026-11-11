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
    this.holdResumeDelay = const Duration(seconds: 15),
  });

  final AutoAdvanceCallback onAdvance;
  final Duration advanceInterval;
  final Duration resumeDelay;
  final Duration holdResumeDelay;

  Timer? _advanceTimer;
  Timer? _resumeTimer;
  final Set<Object> _interactionHolds = <Object>{};
  bool _detailOpen = false;
  bool _disposed = false;
  bool get isPaused =>
      _detailOpen ||
      _interactionHolds.isNotEmpty ||
      _resumeTimer?.isActive == true ||
      _disposed;

  void start() {
    if (_disposed || _detailOpen) return;
    _startAdvanceTimer();
  }

  void registerUserInteraction() {
    if (_disposed) return;
    _cancelTimers();
    if (_detailOpen || _interactionHolds.isNotEmpty) return;
    _resumeTimer = Timer(resumeDelay, _startAdvanceTimer);
  }

  /// Keeps this carousel stopped while a pointer remains over or pressed on it.
  ///
  /// [source] lets mouse hover and touch/pen presses overlap safely. Movement
  /// resumes only after every active source has ended.
  void beginInteractionHold(Object source) {
    if (_disposed) return;
    _interactionHolds.add(source);
    _cancelTimers();
  }

  /// Ends a continuous pointer interaction and advances after 15 idle seconds.
  void endInteractionHold(Object source) {
    if (_disposed || !_interactionHolds.remove(source)) return;
    if (_detailOpen || _interactionHolds.isNotEmpty) return;
    _scheduleResumeAfterHold();
  }

  void pauseForBookDetail() {
    if (_disposed) return;
    _detailOpen = true;
    _cancelTimers();
  }

  void resumeAfterBookDetail() {
    if (_disposed) return;
    _detailOpen = false;
    if (_interactionHolds.isNotEmpty) return;
    _scheduleResumeAfterHold();
  }

  void dispose() {
    _disposed = true;
    _interactionHolds.clear();
    _cancelTimers();
  }

  void _startAdvanceTimer() {
    if (_disposed || _detailOpen || _interactionHolds.isNotEmpty) return;
    _advanceTimer?.cancel();
    _advanceTimer = Timer.periodic(advanceInterval, (_) => onAdvance());
  }

  void _scheduleResumeAfterHold() {
    _cancelTimers();
    _resumeTimer = Timer(holdResumeDelay, () {
      if (_disposed || _detailOpen || _interactionHolds.isNotEmpty) return;
      onAdvance();
      _startAdvanceTimer();
    });
  }

  void _cancelTimers() {
    _advanceTimer?.cancel();
    _resumeTimer?.cancel();
    _advanceTimer = null;
    _resumeTimer = null;
  }
}
