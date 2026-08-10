import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../tokens.dart';

/// Minus/percentage/plus stepper cycling [AppState.textScaleSteps], plus a
/// live preview line rendered at the current scale. Originally built for
/// Settings' "Text size" section; reused verbatim by the Reader's "Aa"
/// bottom-sheet control (design/README.md §02 — "40px circular 'Aa' text-
/// size control") so both entry points to the same [AppState.textScale]
/// step through one implementation.
class TextScaleStepper extends StatelessWidget {
  const TextScaleStepper({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appState = context.watch<AppState>();
    final scale = appState.textScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _StepButton(
              icon: '−',
              semanticLabel: 'Decrease text size',
              onTap: appState.stepTextScaleDown,
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 52,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.jetBrainsMono,
                  fontSize: AppTypeScale.uiTextSize,
                  color: tokens.text2,
                ),
              ),
            ),
            const SizedBox(width: 14),
            _StepButton(
              icon: '+',
              semanticLabel: 'Increase text size',
              onTap: appState.stepTextScaleUp,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(AppGeometry.radiusBlock),
          ),
          child: Text(
            'The quick brown fox jumps over the lazy dog.',
            style: TextStyle(
              fontFamily: AppFonts.ibmPlexSans,
              fontSize: AppTypeScale.bodySize * scale,
              height: AppTypeScale.bodyLineHeight,
              color: tokens.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String icon;
  final String semanticLabel;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: AppGeometry.minTapTarget,
      height: AppGeometry.minTapTarget,
      child: Material(
        color: tokens.panel2,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: Center(
              child: Text(
                icon,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: tokens.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
