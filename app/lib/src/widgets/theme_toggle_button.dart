import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../tokens.dart';

/// The 34px circular `panel2`-filled theme toggle from design/README.md
/// §01's Library header spec, reusable wherever a light⇄dark toggle is
/// needed (Task 4 puts one in the Library header; Settings — this task —
/// puts an equivalent selector alongside it, both driving [AppState]).
///
/// Shows a moon glyph when the app is currently rendering light (tap to go
/// dark) and a sun glyph when currently dark (tap to go light) — mirrors
/// [AppState.toggleTheme]'s "flip relative to the *effective* brightness"
/// contract so it does the right thing even while [AppState.themeMode] is
/// still `system`.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  static const double diameter = 34;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Material(
        color: tokens.panel2,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => appState.toggleTheme(Theme.of(context).brightness),
          child: Center(
            child: Text(
              isDark ? '☀' : '☾',
              style: TextStyle(
                fontSize: AppTypeScale.themeToggleGlyphSize,
                color: tokens.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
