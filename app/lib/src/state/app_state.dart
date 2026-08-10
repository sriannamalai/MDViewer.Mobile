import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's UI-preferences store: theme mode and the reader text-scale
/// step, both persisted via `shared_preferences` and sanitized on load so a
/// corrupt/hand-edited prefs blob degrades to the default instead of
/// crashing boot (same "sanitize() never throws" rule VaultState follows
/// for its own persisted blobs — see vault_state.dart).
///
/// [textScale] is *not* wired into Flutter's own text scaling (MediaQuery) —
/// design/README.md's "State management" section lists it as the input to
/// the Reader's rendered-document CSS scale (`:root{font-size:calc(100% *
/// SCALE)}`, per the plan's Task 5), not a multiplier on app chrome text.
/// UI chrome sizes come from AppTypeScale unconditionally.
class AppState extends ChangeNotifier {
  static const _themeModeKey = 'app.themeMode';
  static const _textScaleKey = 'app.textScale';

  /// Bounded text-scale steps the Settings stepper and Reader's Aa control
  /// cycle through. Any persisted/requested value not in this list is
  /// sanitized to [defaultTextScale].
  static const List<double> textScaleSteps = [0.85, 1.0, 1.15, 1.3];
  static const double defaultTextScale = 1.0;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  double _textScale = defaultTextScale;
  double get textScale => _textScale;

  /// Index of [textScale] within [textScaleSteps]; always resolves (the
  /// invariant [_sanitizeTextScale] upholds is that [_textScale] is always
  /// exactly one of [textScaleSteps]).
  int get textScaleStepIndex => textScaleSteps.indexOf(_textScale);

  bool _ready = false;
  bool get ready => _ready;

  /// Loads persisted preferences. Safe to call more than once (a no-op
  /// after the first successful load) so callers that don't know whether
  /// init already ran — e.g. a splash gate racing app startup — can call it
  /// unconditionally.
  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();

    _themeMode = _sanitizeThemeMode(prefs.getString(_themeModeKey));
    _textScale = _sanitizeTextScale(prefs.getDouble(_textScaleKey));

    _ready = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _encodeThemeMode(mode));
  }

  /// Flips between light and dark relative to [currentBrightness] — the
  /// *effective* brightness the caller is currently rendering with (which,
  /// under [ThemeMode.system], may not match [themeMode] at all). This is
  /// the Library header / Settings toggle's "light ⇄ dark" behavior per
  /// design/README.md §Interactions: it always lands on an explicit mode,
  /// never back on `system`.
  Future<void> toggleTheme(Brightness currentBrightness) {
    final next = currentBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    return setThemeMode(next);
  }

  Future<void> setTextScale(double scale) async {
    final sanitized = _sanitizeTextScale(scale);
    if (_textScale == sanitized) return;
    _textScale = sanitized;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, sanitized);
  }

  /// Steps to the next-largest allowed scale; a no-op at the top of
  /// [textScaleSteps].
  Future<void> stepTextScaleUp() {
    final i = textScaleStepIndex;
    if (i < 0 || i >= textScaleSteps.length - 1) {
      return setTextScale(textScaleSteps.last);
    }
    return setTextScale(textScaleSteps[i + 1]);
  }

  /// Steps to the next-smallest allowed scale; a no-op at the bottom of
  /// [textScaleSteps].
  Future<void> stepTextScaleDown() {
    final i = textScaleStepIndex;
    if (i <= 0) return setTextScale(textScaleSteps.first);
    return setTextScale(textScaleSteps[i - 1]);
  }

  static ThemeMode _sanitizeThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        // Missing key (fresh install) or an unrecognized/corrupt value —
        // both degrade to the documented default rather than throwing.
        return ThemeMode.system;
    }
  }

  static String _encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// A persisted/requested value only survives if it's (within floating
  /// point tolerance) one of [textScaleSteps]; anything else — missing key,
  /// out-of-range double, NaN from a corrupt blob — falls back to
  /// [defaultTextScale].
  static double _sanitizeTextScale(double? raw) {
    if (raw == null) return defaultTextScale;
    for (final step in textScaleSteps) {
      if ((raw - step).abs() < 0.001) return step;
    }
    return defaultTextScale;
  }
}
