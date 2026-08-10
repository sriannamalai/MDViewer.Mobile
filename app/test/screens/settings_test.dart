// SettingsScreen wiring: theme selector and text-size stepper both drive
// AppState (design/README.md's brief: "theme selector, text-size stepper
// ... version footer").

import 'package:app/src/screens/settings.dart';
import 'package:app/src/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(AppState appState) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tapping Dark sets AppState.themeMode', (tester) async {
    final appState = AppState();
    await appState.init();

    await tester.pumpWidget(_wrap(appState));
    await tester.pump();

    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(appState.themeMode, ThemeMode.dark);
  });

  testWidgets('tapping Light sets AppState.themeMode', (tester) async {
    final appState = AppState();
    await appState.init();
    await appState.setThemeMode(ThemeMode.dark);

    await tester.pumpWidget(_wrap(appState));
    await tester.pump();

    await tester.tap(find.text('Light'));
    await tester.pump();

    expect(appState.themeMode, ThemeMode.light);
  });

  testWidgets(
    'the text-size stepper steps AppState.textScale and shows a live percentage',
    (tester) async {
      final appState = AppState();
      await appState.init();

      await tester.pumpWidget(_wrap(appState));
      await tester.pump();

      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.text('+'));
      await tester.pump();

      expect(appState.textScale, 1.15);
      expect(find.text('115%'), findsOneWidget);

      await tester.tap(find.text('−'));
      await tester.pump();

      expect(appState.textScale, 1.0);
      expect(find.text('100%'), findsOneWidget);
    },
  );

  testWidgets('shows a version footer', (tester) async {
    final appState = AppState();
    await appState.init();

    await tester.pumpWidget(_wrap(appState));
    await tester.pump();

    expect(find.textContaining('MDViewer.Mobile'), findsOneWidget);
  });
}
