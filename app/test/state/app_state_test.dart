import 'package:app/src/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppState.init defaults', () {
    test('defaults to system theme and 1.0 text scale with no prefs', () async {
      final state = AppState();
      expect(state.ready, false);

      await state.init();

      expect(state.ready, true);
      expect(state.themeMode, ThemeMode.system);
      expect(state.textScale, 1.0);
    });

    test('init is idempotent — a second call is a no-op', () async {
      final state = AppState();
      await state.init();
      await state.setThemeMode(ThemeMode.dark);

      await state.init(); // must not reset themeMode back to system

      expect(state.themeMode, ThemeMode.dark);
    });
  });

  group('theme mode persistence round-trip', () {
    test('setThemeMode persists and a fresh AppState loads it', () async {
      final first = AppState();
      await first.init();

      await first.setThemeMode(ThemeMode.dark);
      expect(first.themeMode, ThemeMode.dark);

      final second = AppState();
      await second.init();

      expect(second.themeMode, ThemeMode.dark);
    });

    test('round-trips light too', () async {
      final first = AppState();
      await first.init();
      await first.setThemeMode(ThemeMode.light);

      final second = AppState();
      await second.init();

      expect(second.themeMode, ThemeMode.light);
    });

    test('an unrecognized persisted value sanitizes to system', () async {
      SharedPreferences.setMockInitialValues({'app.themeMode': 'sepia'});
      final state = AppState();

      await state.init();

      expect(state.themeMode, ThemeMode.system);
    });

    test(
      'toggleTheme flips relative to the current effective brightness',
      () async {
        final state = AppState();
        await state.init();
        expect(state.themeMode, ThemeMode.system);

        await state.toggleTheme(Brightness.light);
        expect(state.themeMode, ThemeMode.dark);

        await state.toggleTheme(Brightness.dark);
        expect(state.themeMode, ThemeMode.light);
      },
    );

    test('setThemeMode notifies listeners', () async {
      final state = AppState();
      await state.init();
      var notified = 0;
      state.addListener(() => notified++);

      await state.setThemeMode(ThemeMode.dark);

      expect(notified, 1);
    });

    test(
      'setting the same mode again does not notify or rewrite prefs',
      () async {
        final state = AppState();
        await state.init();
        await state.setThemeMode(ThemeMode.dark);
        var notified = 0;
        state.addListener(() => notified++);

        await state.setThemeMode(ThemeMode.dark);

        expect(notified, 0);
      },
    );
  });

  group('textScale bounds', () {
    test('setTextScale accepts an exact step', () async {
      final state = AppState();
      await state.init();

      await state.setTextScale(1.3);

      expect(state.textScale, 1.3);
      expect(state.textScaleStepIndex, AppState.textScaleSteps.length - 1);
    });

    test(
      'setTextScale sanitizes an out-of-band value to the default',
      () async {
        final state = AppState();
        await state.init();

        await state.setTextScale(2.5);

        expect(state.textScale, AppState.defaultTextScale);
      },
    );

    test('stepTextScaleUp/Down move through the bounded steps', () async {
      final state = AppState();
      await state.init();
      expect(state.textScale, 1.0);

      await state.stepTextScaleUp();
      expect(state.textScale, 1.15);

      await state.stepTextScaleUp();
      expect(state.textScale, 1.3);

      await state.stepTextScaleDown();
      expect(state.textScale, 1.15);
    });

    test('stepTextScaleUp is a no-op at the top of the range', () async {
      final state = AppState();
      await state.init();
      await state.setTextScale(1.3);

      await state.stepTextScaleUp();

      expect(state.textScale, 1.3);
    });

    test('stepTextScaleDown is a no-op at the bottom of the range', () async {
      final state = AppState();
      await state.init();
      await state.setTextScale(0.85);

      await state.stepTextScaleDown();

      expect(state.textScale, 0.85);
    });

    test(
      'a corrupt persisted textScale sanitizes to the default on load',
      () async {
        SharedPreferences.setMockInitialValues({'app.textScale': 0.42});
        final state = AppState();

        await state.init();

        expect(state.textScale, AppState.defaultTextScale);
      },
    );

    test('textScale persists and a fresh AppState loads it', () async {
      final first = AppState();
      await first.init();
      await first.setTextScale(0.85);

      final second = AppState();
      await second.init();

      expect(second.textScale, 0.85);
    });
  });
}
