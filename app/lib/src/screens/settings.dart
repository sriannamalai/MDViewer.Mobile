import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mdviewer_version.dart';
import '../state/app_state.dart';
import '../tokens.dart';

/// The mini Settings screen — theme selector, text-size stepper (with a
/// live preview line), and a version footer, all built from
/// [AppTokens]/[AppTypeScale]/[AppGeometry] per the plan's "tokens-only
/// design" requirement. Simple and spacious rather than dense, per
/// design/README.md §Interactions' 44px+ tap-target rule.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          children: [
            Text(
              'Settings',
              style: TextStyle(
                fontFamily: AppFonts.sourceSerif4,
                fontSize: AppTypeScale.h2Size,
                fontWeight: AppTypeScale.h2Weight,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 28),
            const _SectionLabel('Appearance'),
            const SizedBox(height: 10),
            const _ThemeModeSelector(),
            const SizedBox(height: 32),
            const _SectionLabel('Text size'),
            const SizedBox(height: 10),
            const _TextScaleStepper(),
            const SizedBox(height: 40),
            const _VersionFooter(),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: AppFonts.ibmPlexSans,
        fontSize: AppTypeScale.uiLabelSize,
        fontWeight: AppTypeScale.uiLabelWeight,
        letterSpacing: AppTypeScale.uiLabelLetterSpacing,
        color: tokens.text3,
      ),
    );
  }
}

/// System / Light / Dark segmented selector driving [AppState.themeMode]
/// directly (unlike [ThemeToggleButton], which only ever lands on an
/// explicit light/dark — this selector is the one place `system` can be
/// chosen).
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  static String _label(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appState = context.watch<AppState>();

    return Row(
      children: ThemeMode.values.map((mode) {
        final active = appState.themeMode == mode;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: active ? tokens.accentSoft : tokens.panel2,
              borderRadius: BorderRadius.circular(AppGeometry.radiusButtonMax),
              child: InkWell(
                borderRadius: BorderRadius.circular(
                  AppGeometry.radiusButtonMax,
                ),
                onTap: () => appState.setThemeMode(mode),
                child: Container(
                  height: AppGeometry.minTapTarget,
                  alignment: Alignment.center,
                  child: Text(
                    _label(mode),
                    style: TextStyle(
                      fontFamily: AppFonts.ibmPlexSans,
                      fontSize: AppTypeScale.uiTextSize,
                      fontWeight: active
                          ? FontWeight.w600
                          : AppTypeScale.uiTextWeightMin,
                      color: active ? tokens.accent : tokens.text2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Minus/percentage/plus stepper cycling [AppState.textScaleSteps], plus a
/// live preview line rendered at the current scale so the effect on prose
/// (this is the scale Task 5's Reader passes into the renderer's stylesheet
/// override, not a multiplier on this screen's own chrome) is visible
/// before leaving Settings.
class _TextScaleStepper extends StatelessWidget {
  const _TextScaleStepper();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appState = context.watch<AppState>();
    final scale = appState.textScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Text(
        'MDViewer.Mobile · libmdviewer v${tryMdviewerVersion() ?? 'dev'}',
        style: TextStyle(
          fontFamily: AppFonts.jetBrainsMono,
          fontSize: AppTypeScale.uiLabelSize,
          color: tokens.text3,
        ),
      ),
    );
  }
}
