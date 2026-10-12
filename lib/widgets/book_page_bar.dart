import 'package:flutter/material.dart';

/// A page control independent of the width of the nine visible book cards.
/// One completed drag changes one page, never continuously fetches pages.
class BookPageBar extends StatefulWidget {
  const BookPageBar({
    super.key,
    required this.pageNumber,
    required this.canLoadPrevious,
    required this.hasMore,
    required this.isLoading,
    required this.onNext,
    required this.onPrevious,
  });

  final int pageNumber;
  final bool canLoadPrevious;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  State<BookPageBar> createState() => _BookPageBarState();
}

class _BookPageBarState extends State<BookPageBar> {
  double? _dragValue;

  double get _restValue => !widget.canLoadPrevious
      ? 0
      : widget.hasMore
      ? 0.5
      : 1;

  @override
  void didUpdateWidget(covariant BookPageBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.isLoading != widget.isLoading) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !widget.isLoading && (widget.canLoadPrevious || widget.hasMore);
    return SizedBox(
      height: 32,
      child: Tooltip(
        message: '右へドラッグして次の9冊、左へドラッグして前の9冊',
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: _dragValue ?? _restValue,
            semanticFormatterCallback: (_) =>
                '${widget.pageNumber}ページ目、左右に操作して9冊ずつ移動',
            onChanged: enabled
                ? (value) => setState(() => _dragValue = value)
                : null,
            onChangeEnd: enabled
                ? (value) {
                    final delta = value - _restValue;
                    setState(() => _dragValue = null);
                    if (delta >= 0.15 && widget.hasMore) {
                      widget.onNext();
                    } else if (delta <= -0.15 && widget.canLoadPrevious) {
                      widget.onPrevious();
                    }
                  }
                : null,
          ),
        ),
      ),
    );
  }
}
