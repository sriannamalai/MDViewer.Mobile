import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mdviewer_version.dart';
import '../state/app_state.dart';
import '../tokens.dart';
import '../widgets/text_scale_stepper.dart';

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
            const TextScaleStepper(),
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
