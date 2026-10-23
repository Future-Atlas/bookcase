import 'package:flutter/material.dart';

/// A star-shaped control for ratings from 0.0 to 5.0 in 0.1 increments.
///
/// The ruler draws every one of the 51 tick positions, including on narrow
/// mobile layouts where Flutter's built-in Slider may omit crowded ticks.
class StarRatingSlider extends StatelessWidget {
  const StarRatingSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static const double _thumbDiameter = 24;

  @override
  Widget build(BuildContext context) {
    final snappedValue = (value * 10).round().clamp(0, 50) / 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '星評価',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const Spacer(),
            Text(
              '${snappedValue.toStringAsFixed(1)} / 5.0',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE0B400),
              ),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Flutter's 24px transparent thumb and the visible star have the
            // same travel range: from x=12 to x=width-12.
            final travel = (constraints.maxWidth - _thumbDiameter)
                .clamp(0.0, double.infinity)
                .toDouble();
            final starLeft = travel * snappedValue / 5.0;
            return SizedBox(
              height: 60,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: _RatingRulerPainter()),
                  ),
                  Positioned.fill(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbColor: Colors.transparent,
                        overlayColor: Colors.transparent,
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: _thumbDiameter / 2,
                          disabledThumbRadius: _thumbDiameter / 2,
                          elevation: 0,
                          pressedElevation: 0,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                        tickMarkShape: const RoundSliderTickMarkShape(
                          tickMarkRadius: 0,
                        ),
                        showValueIndicator: ShowValueIndicator.never,
                      ),
                      child: Slider(
                        min: 0,
                        max: 5,
                        divisions: 50,
                        value: snappedValue,
                        onChanged: (next) =>
                            onChanged((next * 10).round() / 10.0),
                        semanticFormatterCallback: (next) =>
                            '${next.toStringAsFixed(1)}点',
                      ),
                    ),
                  ),
                  Positioned(
                    left: starLeft,
                    top: 18,
                    child: const IgnorePointer(
                      child: Icon(
                        Icons.star,
                        size: _thumbDiameter,
                        color: Color(0xFFE0B400),
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(11, (index) {
              final label = index == 0 ? '0' : (index / 2).toStringAsFixed(1);
              return Text(
                label,
                style: const TextStyle(fontSize: 9, color: Colors.black87),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _RatingRulerPainter extends CustomPainter {
  const _RatingRulerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const margin = StarRatingSlider._thumbDiameter / 2;
    final width = size.width - margin * 2;
    if (width <= 0) return;

    final y = size.height / 2;
    final trackPaint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(margin, y), Offset(size.width - margin, y), trackPaint);

    final tickPaint = Paint()
      ..color = const Color(0xFF757575)
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 50; tick++) {
      final x = margin + width * tick / 50;
      final isLabeledTick = tick % 5 == 0;
      canvas.drawLine(
        Offset(x, y + 5),
        Offset(x, y + (isLabeledTick ? 14 : 10)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RatingRulerPainter oldDelegate) => false;
}
