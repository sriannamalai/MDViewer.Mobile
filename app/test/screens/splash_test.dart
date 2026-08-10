// Tests for SplashGate's timing contract (design/README.md §00: "Dismisses
// to Library when the vault index is ready" + the plan's "min display
// ~600ms so it doesn't flash"). Uses a fake, device-free VaultProvider pair
// (mirrors test/state/vault_state_test.dart's FakeVaultProvider) so these
// run under plain `flutter test`, no simulator/emulator required.

import 'dart:typed_data';

import 'package:app/src/screens/shell.dart';
import 'package:app/src/screens/splash.dart';
import 'package:app/src/screens/splash_gate.dart';
import 'package:app/src/state/app_state.dart';
import 'package:app/src/state/vault_state.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_grant.dart';
import 'package:app/src/vault/vault_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVaultProvider implements VaultProvider {
  _FakeVaultProvider({Map<String, Uint8List>? files}) : files = files ?? {};

  final Map<String, Uint8List> files;

  @override
  Future<VaultGrant?> pickFolder() async => null;

  @override
  Future<bool> restore(VaultGrant grant) async => true;

  @override
  Future<List<String>> list(VaultGrant grant) async => files.keys.toList();

  @override
  Future<Uint8List> read(VaultEntry entry) async {
    final bytes = files[entry.relPath];
    if (bytes == null) throw StateError('not found: ${entry.relPath}');
    return bytes;
  }
}

VaultState _fakeVaultState() => VaultState(
  sampleProvider: _FakeVaultProvider(),
  folderProvider: _FakeVaultProvider(),
);

// SplashGate transitions to AppShell, whose Settings and Library tabs (both
// built eagerly — IndexedStack mounts all its children up front, not just
// the visible one) read AppState/VaultState via Provider — so both must be
// in scope even for tests that never navigate away from the splash itself.
Widget _wrap(Widget child, VaultState vaultState) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>(create: (_) => AppState()),
      ChangeNotifierProvider<VaultState>.value(value: vaultState),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the splash screen immediately', (tester) async {
    final vaultState = _fakeVaultState();

    await tester.pumpWidget(
      _wrap(
        SplashGate(
          vaultState: vaultState,
          minDisplay: const Duration(milliseconds: 300),
        ),
        vaultState,
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    // Let the pending min-display timer resolve so it doesn't leak past
    // this test's teardown.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'enforces the minimum display even when the vault is instantly ready',
    (tester) async {
      final vaultState = _fakeVaultState();

      await tester.pumpWidget(
        _wrap(
          SplashGate(
            vaultState: vaultState,
            minDisplay: const Duration(milliseconds: 300),
          ),
          vaultState,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(SplashScreen),
        findsOneWidget,
        reason: 'still under the 300ms floor',
      );
      expect(vaultState.ready, true, reason: 'vault init itself is done');

      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
    },
  );

  testWidgets('transitions to the shell once VaultState.init completes', (
    tester,
  ) async {
    final vaultState = VaultState(
      sampleProvider: _FakeVaultProvider(files: {'Welcome.md': Uint8List(0)}),
      folderProvider: _FakeVaultProvider(),
    );

    await tester.pumpWidget(
      _wrap(
        SplashGate(vaultState: vaultState, minDisplay: Duration.zero),
        vaultState,
      ),
    );
    // A handful of plain pumps flushes the asset-read/prefs futures without
    // needing pumpAndSettle (which would spin forever against the splash's
    // repeating loading-bar animation while it's still on screen).
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(vaultState.ready, true);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('does not re-run VaultState.init if it is already ready', (
    tester,
  ) async {
    final vaultState = _fakeVaultState();
    await vaultState.init();
    expect(vaultState.ready, true);

    await tester.pumpWidget(
      _wrap(
        SplashGate(
          vaultState: vaultState,
          minDisplay: const Duration(milliseconds: 50),
        ),
        vaultState,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(AppShell), findsOneWidget);
  });
}
