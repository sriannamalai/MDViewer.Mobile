import 'package:flutter/material.dart';

import 'logo_mark.dart';

/// The app icon tile used in the Library header (design/README.md §01:
/// "26px app icon tile — charcoal gradient, bracket mark"). Reuses
/// [LogoMark]'s compact variant for the mark itself; the charcoal gradient
/// tile is new here.
///
/// Colors are transcribed verbatim from the HTML reference's screen-01
/// markup (`background:linear-gradient(150deg,#2a2d34 0%,#17181c 70%);
/// box-shadow:inset 0 0 0 1px rgba(255,255,255,.06)`) rather than pulled
/// from `AppTokens` — like splash.dart's background gradient, this tile's
/// identity is a fixed brand asset that doesn't change with the app's
/// light/dark theme, so it isn't part of TOKENS.md's app palette.
class AppIconTile extends StatelessWidget {
  const AppIconTile({super.key, this.size = 26});

  final double size;

  // CSS `150deg` converted to a begin/end Alignment pair using the same
  // `dx = sin(theta), dy = -cos(theta)` mapping splash.dart's background
  // gradient comment documents (0deg = "to top", measured clockwise):
  // sin(150deg) = 0.5, -cos(150deg) = 0.866.
  static const _gradient = LinearGradient(
    begin: Alignment(-0.5, -0.866),
    end: Alignment(0.5, 0.866),
    stops: [0.0, 0.7],
    colors: [Color(0xFF2A2D34), Color(0xFF17181C)],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(size * 7 / 26),
        border: Border.all(color: const Color(0x0FFFFFFF)), // ~.06 alpha
      ),
      alignment: Alignment.center,
      child: LogoMark(size: size, compact: true),
    );
  }
}
