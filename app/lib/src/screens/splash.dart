import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mdviewer_version.dart';
import '../tokens.dart';
import '../widgets/logo_mark.dart';

/// Splash per design/README.md §00 — full-screen dark gradient, coral
/// radial glow, bracket-mark logo, two-tone wordmark, tagline, 104×3
/// indeterminate loading bar, and a mono version line. Always renders with
/// the dark palette and a light-content status bar *regardless of the
/// app's current [AppState.themeMode]* — this screen doesn't read
/// `AppTokens.of(context)` at all, only the fixed [AppTokens.dark] set and
/// a handful of splash-only literals the design calls out that aren't in
/// TOKENS.md (the background gradient stops, the glow, the loading-bar
/// fill gradient).
///
/// This widget is purely presentational — [SplashGate] owns the "how long
/// to show it" timing/readiness logic.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // design/README.md §00: "linear-gradient(168deg, #33373f 0%, #1d1f25
  // 42%, #131418 72%, #0f1013 100%)". CSS 168deg (measured from +y, i.e.
  // "up") converted to an Alignment begin/end pair: mostly top-to-bottom
  // with a slight left-to-right lean.
  static const _backgroundGradient = LinearGradient(
    begin: Alignment(-0.21, -0.98),
    end: Alignment(0.21, 0.98),
    stops: [0.0, 0.42, 0.72, 1.0],
    colors: [
      Color(0xFF33373F),
      Color(0xFF1D1F25),
      Color(0xFF131418),
      Color(0xFF0F1013),
    ],
  );

  // "Soft coral radial glow ... rgba(226,113,74,.20) → transparent @ 68%".
  static const _glowGradient = RadialGradient(
    colors: [
      Color(0x33E2714A), // ~20%
      Color(0x12E2714A), // ~7%
      Color(0x00E2714A),
    ],
    stops: [0.0, 0.42, 0.68],
  );

  static const double _glowDiameter = 380;
  static const double _logoSize = 132;

  @override
  Widget build(BuildContext context) {
    final dark = AppTokens.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1013),
        // LayoutBuilder wraps the whole Stack (rather than sitting as one of
        // its children) so the glow's Positioned — which needs the screen's
        // resolved size to reproduce CSS's `top:24%` — stays a *direct*
        // child of Stack; a Positioned nested one level deeper (inside a
        // LayoutBuilder that is itself a Stack child) isn't a valid
        // ParentDataWidget placement and throws at layout time.
        body: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: _backgroundGradient),
                ),
                // CSS `position:absolute; top:24%` positions the glow's
                // *top edge*, not its center — so no half-diameter offset.
                Positioned(
                  top: height * 0.24,
                  left: (width - _glowDiameter) / 2,
                  width: _glowDiameter,
                  height: _glowDiameter,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _glowGradient,
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Approximates the SVG's `filter: drop-shadow(0 10px
                      // 34px rgba(226,113,74,.22))` — a soft, roughly
                      // circular warm smudge behind the mark's bounding box.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_logoSize / 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x38E2714A), // ~.22 alpha
                              blurRadius: 34,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const LogoMark(size: _logoSize),
                      ),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontFamily: AppFonts.ibmPlexSans,
                            fontSize: AppTypeScale.splashWordmarkSize,
                            fontWeight: FontWeight.w600,
                            letterSpacing:
                                AppTypeScale.splashWordmarkLetterSpacing,
                          ),
                          children: [
                            TextSpan(
                              text: 'MarkDown',
                              style: TextStyle(color: dark.text),
                            ),
                            TextSpan(
                              text: 'Viewer',
                              style: TextStyle(
                                color: dark.text3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Markdown, rendered beautifully — offline',
                        style: TextStyle(
                          fontFamily: AppFonts.ibmPlexSans,
                          fontSize: AppTypeScale.splashTaglineSize,
                          color: dark.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 44,
                  child: Column(
                    children: [
                      const _LoadingBar(),
                      const SizedBox(height: 14),
                      Text(
                        'v${tryMdviewerVersion() ?? 'dev'}',
                        style: TextStyle(
                          fontFamily: AppFonts.jetBrainsMono,
                          fontSize: AppTypeScale.uiMetaSizeMin,
                          color: dark.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The indeterminate 104×3 loading bar: a rounded track (`line2`) with a
/// gradient-filled segment sweeping left-to-right on a loop.
class _LoadingBar extends StatefulWidget {
  const _LoadingBar();

  @override
  State<_LoadingBar> createState() => _LoadingBarState();
}

class _LoadingBarState extends State<_LoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  static const double _width = 104;
  static const double _height = 3;
  static const double _segmentWidth = _width * 0.38;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppTokens.dark.line2),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final travel = _width + _segmentWidth;
              final x = -_segmentWidth + travel * _controller.value;
              return Stack(
                children: [
                  Positioned(
                    left: x,
                    top: 0,
                    width: _segmentWidth,
                    height: _height,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB27D), Color(0xFFE2714A)],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
