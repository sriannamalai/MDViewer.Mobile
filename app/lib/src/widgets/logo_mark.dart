import 'package:flutter/material.dart';

/// The bracket-mark logo — a `CustomPainter` reproduction of
/// `design/assets/icon.svg` (viewBox `0 0 24 24`), used at 132px on the
/// Splash screen (design/README.md §00) and reusable at the Library
/// header's 26px icon-tile scale (Task 4).
///
/// Reproduced as vector paths rather than bundling `flutter_svg` (not a
/// declared dependency — see Task 1's pubspec) so this stays a
/// zero-new-dependency widget; every coordinate below is transcribed
/// verbatim from the SVG's `<path>` `d` attributes, scaled by `size/24`.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, required this.size, this.compact = false});

  final double size;

  /// When true, renders the reduced icon-tile variant design/README.md
  /// §01's header uses at 26px: the HTML reference's screen-01 markup
  /// (`<svg viewBox="0 0 24 24" style="width:26px; height:26px;">`) draws
  /// only the two outer brackets plus a flat-color "M" stroke — it omits
  /// the two faint inner brackets and the diagonal gradient the splash-scale
  /// mark (`compact: false`, the default) uses, presumably because both
  /// wash out at icon-tile size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoMarkPainter(compact: compact)),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  _LogoMarkPainter({this.compact = false});

  final bool compact;

  // stroke="#e2714a" opacity="0.22" / opacity="0.45" from icon.svg — baked
  // into the ARGB literal rather than Color.withValues so the exact bytes
  // match the SVG's rendered alpha (0.22*255≈56, 0.45*255≈115).
  static const _outerFaint = Color(0x38E2714A);
  static const _outerMid = Color(0x73E2714A);
  static const _gradientStart = Color(0xFFFFB27D);
  static const _gradientEnd = Color(0xFFE2714A);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;

    Paint stroke(Color color, double width) {
      return Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }

    void polyline(List<Offset> points, Paint paint) {
      final path = Path()
        ..moveTo(points.first.dx * scale, points.first.dy * scale);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx * scale, p.dy * scale);
      }
      canvas.drawPath(path, paint);
    }

    if (!compact) {
      // `M8.6 7.6 L5.6 12 L8.6 16.4` — inner-left faint bracket.
      polyline(const [
        Offset(8.6, 7.6),
        Offset(5.6, 12),
        Offset(8.6, 16.4),
      ], stroke(_outerFaint, 1.7));
      // `M15.4 7.6 L18.4 12 L15.4 16.4` — inner-right faint bracket.
      polyline(const [
        Offset(15.4, 7.6),
        Offset(18.4, 12),
        Offset(15.4, 16.4),
      ], stroke(_outerFaint, 1.7));
    }
    // `M7.3 6.3 L3.8 12 L7.3 17.7` — outer-left bracket.
    polyline(const [
      Offset(7.3, 6.3),
      Offset(3.8, 12),
      Offset(7.3, 17.7),
    ], stroke(_outerMid, 1.9));
    // `M16.7 6.3 L20.2 12 L16.7 17.7` — outer-right bracket.
    polyline(const [
      Offset(16.7, 6.3),
      Offset(20.2, 12),
      Offset(16.7, 17.7),
    ], stroke(_outerMid, 1.9));

    // `M8.8 16 L8.8 8.8 L12 12.4 L15.2 8.8 L15.2 16` — the "M" glyph. The
    // splash-scale mark strokes it with a gradient (`<linearGradient
    // id="g" x1="8.8" y1="8.8" x2="15.2" y2="16">`); the compact icon-tile
    // variant strokes it flat `#ffb27d` per the header markup's plain
    // `stroke="#ffb27d"` (no gradient def at that scale).
    final mPaint = compact
        ? stroke(_gradientStart, 2.2)
        : (Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 * scale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..shader =
                const LinearGradient(
                  colors: [_gradientStart, _gradientEnd],
                ).createShader(
                  Rect.fromPoints(
                    Offset(8.8 * scale, 8.8 * scale),
                    Offset(15.2 * scale, 16 * scale),
                  ),
                ));
    polyline(const [
      Offset(8.8, 16),
      Offset(8.8, 8.8),
      Offset(12, 12.4),
      Offset(15.2, 8.8),
      Offset(15.2, 16),
    ], mPaint);
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter oldDelegate) =>
      oldDelegate.compact != compact;
}
