// AppShell tests: tab switching (design/README.md §Interactions — "Tabs
// switch root screens") and that switching preserves each root's own
// widget/scroll state rather than rebuilding it from scratch, per the
// plan's Task 3 checklist ("tab switching preserves each tab's state").

import 'package:app/src/screens/library.dart';
import 'package:app/src/screens/settings.dart';
import 'package:app/src/screens/shell.dart';
import 'package:app/src/state/app_state.dart';
import 'package:app/src/state/vault_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(AppState appState, VaultState vaultState) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<VaultState>.value(value: vaultState),
    ],
    child: const MaterialApp(home: AppShell()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starts on Library and switches roots on tab tap', (
    tester,
  ) async {
    final appState = AppState();
    await appState.init();
    final vaultState = VaultState();
    await vaultState.init();

    await tester.pumpWidget(_wrap(appState, vaultState));
    await tester.pump();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('appTab-settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('appTab-library')));
    await tester.pumpAndSettle();

    // LibraryScreen stays alive in the IndexedStack the whole time, but
    // re-asserting its presence after switching back confirms the tab
    // actually flipped rather than Settings simply overlaying it.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets(
    'switching away and back preserves a tab root\'s own scroll state',
    (tester) async {
      // A small viewport so Settings' content is guaranteed to overflow and
      // actually be scrollable (the default test surface is roomy enough
      // that Settings' short content list fits without scrolling).
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await appState.init();
      final vaultState = VaultState();
      await vaultState.init();

      await tester.pumpWidget(_wrap(appState, vaultState));
      await tester.pump();

      await tester.tap(find.byKey(const Key('appTab-settings')));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();

      final scrolledPosition = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;
      expect(
        scrolledPosition,
        greaterThan(0),
        reason: 'the drag should have scrolled the Settings list',
      );

      // Switch to another tab and back — if AppShell rebuilt the Settings
      // root from scratch instead of keeping it alive in an IndexedStack,
      // this scroll offset would reset to 0.
      await tester.tap(find.byKey(const Key('appTab-library')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appTab-settings')));
      await tester.pumpAndSettle();

      final restoredPosition = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      expect(restoredPosition, scrolledPosition);
    },
  );
}
