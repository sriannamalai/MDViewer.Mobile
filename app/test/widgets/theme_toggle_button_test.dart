// ThemeToggleButton is exposed by this task for Task 4's Library header
// (design/README.md §01's 34px circular theme toggle) but isn't consumed
// anywhere yet — these tests exercise it standalone so its AppState wiring
// is verified before Task 4 depends on it.

import 'package:app/src/state/app_state.dart';
import 'package:app/src/widgets/theme_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(AppState appState, {required ThemeMode themeMode}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      home: const Scaffold(body: Center(child: ThemeToggleButton())),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a moon glyph in light mode, tapping switches to dark', (
    tester,
  ) async {
    final appState = AppState();
    await appState.init();

    await tester.pumpWidget(_wrap(appState, themeMode: ThemeMode.light));
    await tester.pump();

    expect(find.text('☾'), findsOneWidget);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pump();

    expect(appState.themeMode, ThemeMode.dark);
  });

  testWidgets('shows a sun glyph in dark mode, tapping switches to light', (
    tester,
  ) async {
    final appState = AppState();
    await appState.init();

    await tester.pumpWidget(_wrap(appState, themeMode: ThemeMode.dark));
    await tester.pump();

    expect(find.text('☀'), findsOneWidget);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pump();

    expect(appState.themeMode, ThemeMode.light);
  });
}
