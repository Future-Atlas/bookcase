import 'package:flutter/material.dart';

/// A star-shaped control for ratings from 0.0 to 5.0 in 0.1 increments.
///
/// The slider retains 0.1-step precision without a crowded visual ruler.
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
                    child: CustomPaint(painter: _RatingTrackPainter()),
                  ),
                  Positioned.fill(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbColor: Colors.transparent,
                        overlayColor: Colors.transparent,
                        trackHeight: 2,
                        // Keep the 24px layout geometry, but paint no
                        // circular thumb behind the separate gold star.
                        thumbShape: const _InvisibleSliderThumbShape(),
                        overlayShape: SliderComponentShape.noOverlay,
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
      ],
    );
  }
}

/// Retains the 24px drag geometry without drawing the Slider's default
/// circular thumb. The visible gold star is painted separately above it.
class _InvisibleSliderThumbShape extends SliderComponentShape {
  const _InvisibleSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(StarRatingSlider._thumbDiameter, StarRatingSlider._thumbDiameter);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    // Deliberately blank: never render a dark circle behind the star.
  }
}

class _RatingTrackPainter extends CustomPainter {
  const _RatingTrackPainter();

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
  }

  @override
  bool shouldRepaint(covariant _RatingTrackPainter oldDelegate) => false;
}
