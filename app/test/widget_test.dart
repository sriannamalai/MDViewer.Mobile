// Smoke test for the app root: MDViewerApp builds, shows the splash screen
// first, then transitions to the shell once VaultState's init completes and
// the minimum splash display elapses — without throwing, and without
// leaking a pending Timer/Ticker past the end of the test (the splash's
// indeterminate loading bar and SplashGate's min-display delay both use
// timers that must resolve or be disposed before the test tears down).
//
// Splash's own visual details are covered by test/screens/splash_test.dart;
// the shell/tabs/settings screens each have their own test files.

import 'package:app/main.dart';
import 'package:app/src/screens/shell.dart';
import 'package:app/src/screens/splash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MDViewerApp shows splash, then the shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MDViewerApp());
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);

    // Elapses VaultState.init() (asset-backed, effectively instant) plus
    // SplashGate's default 600ms minimum display.
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });
}
