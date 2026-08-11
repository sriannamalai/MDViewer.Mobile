// LibraryScreen widget tests (design/README.md §01): tree rendering
// (folders-first, badges, child counts), expand/collapse, the Recent
// section + relative times, tap -> recent recorded + Reader navigation
// invoked, the empty-vault prompt, and the search field's tab-switch hook.
//
// Uses the same FakeVaultProvider pattern as vault_state_test.dart so this
// is device-free — no platform channel involved.

import 'dart:convert';

import 'package:app/src/screens/library.dart';
import 'package:app/src/state/app_state.dart';
import 'package:app/src/state/vault_state.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_grant.dart';
import 'package:app/src/vault/vault_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_webview_platform.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

class FakeVaultProvider implements VaultProvider {
  FakeVaultProvider({
    this.pickResult,
    this.pickError,
    this.restoreResult = true,
    Map<String, Uint8List>? files,
  }) : files = files ?? {};

  VaultGrant? pickResult;
  Object? pickError;
  bool restoreResult;
  final Map<String, Uint8List> files;

  @override
  Future<VaultGrant?> pickFolder() async {
    if (pickError != null) throw pickError!;
    return pickResult;
  }

  @override
  Future<bool> restore(VaultGrant grant) async => restoreResult;

  @override
  Future<List<String>> list(VaultGrant grant) async =>
      files.keys.where((p) => p.toLowerCase().endsWith('.md')).toList();

  @override
  Future<Uint8List> read(VaultEntry entry) async {
    final bytes = files[entry.relPath];
    if (bytes == null) throw StateError('not found: ${entry.relPath}');
    return bytes;
  }
}

// LibraryHeader includes a ThemeToggleButton (Task 3), which reads
// Provider<AppState> — so the wrapper needs both providers even though
// these tests don't exercise theme switching directly. Default AppState()
// (themeMode: system) is fine unstarted; nothing here calls init().
Widget _wrap(VaultState vault, {VoidCallback? onOpenSearch}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>(create: (_) => AppState()),
      ChangeNotifierProvider<VaultState>.value(value: vault),
    ],
    child: MaterialApp(
      home: LibraryScreen(onOpenSearch: onOpenSearch ?? () {}),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // navigation.dart's pushReader now routes to the real ReaderScreen
    // (Task 5), which constructs a WebViewController — needs a registered
    // platform even though this suite never exercises webview behavior
    // itself. See fake_webview_platform.dart's doc comment.
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  group('vault tree', () {
    testWidgets('renders folders before files, with a child-count badge', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'vault.grant': jsonEncode({'id': 'g1', 'displayName': 'My Docs'}),
      });
      final folder = FakeVaultProvider(
        files: {
          'docs/Design.md': _bytes('a'),
          'docs/Benchmarks.md': _bytes('b'),
          'README.md': _bytes('c'),
        },
      );
      final vault = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: folder,
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      expect(find.text('MY DOCS'), findsOneWidget);
      expect(find.text('docs'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
      // docs' recursive md count (2 nested files).
      expect(find.text('2'), findsOneWidget);
      // Collapsed by default — nested children aren't rendered yet.
      expect(find.text('Design.md'), findsNothing);

      final docsY = tester.getCenter(find.text('docs')).dy;
      final readmeY = tester.getCenter(find.text('README.md')).dy;
      expect(
        docsY,
        lessThan(readmeY),
        reason: 'folders render before files (VaultIndex.build order)',
      );
    });

    testWidgets('markdown files show the mono "M" badge and a chevron', (
      tester,
    ) async {
      final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
      final vault = VaultState(
        sampleProvider: sample,
        folderProvider: FakeVaultProvider(),
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      expect(find.text('M'), findsOneWidget);
      expect(find.text('›'), findsOneWidget);
    });

    testWidgets('tapping a folder row expands it, revealing nested files', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'vault.grant': jsonEncode({'id': 'g1', 'displayName': 'My Docs'}),
      });
      final folder = FakeVaultProvider(files: {'docs/Design.md': _bytes('a')});
      final vault = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: folder,
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      expect(find.text('Design.md'), findsNothing);

      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();

      expect(find.text('Design.md'), findsOneWidget);

      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();

      expect(find.text('Design.md'), findsNothing);
    });
  });

  group('Recent section', () {
    testWidgets('renders recorded opens with relative-time meta', (
      tester,
    ) async {
      final twoHoursAgo = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'vault.recents': jsonEncode([
          {
            'relPath': 'Welcome.md',
            'source': 'sample',
            'openedAtMs': twoHoursAgo,
          },
        ]),
      });
      final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
      final vault = VaultState(
        sampleProvider: sample,
        folderProvider: FakeVaultProvider(),
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
    });

    testWidgets('is absent entirely when there are no recents', (tester) async {
      final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
      final vault = VaultState(
        sampleProvider: sample,
        folderProvider: FakeVaultProvider(),
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      expect(find.text('RECENT'), findsNothing);
    });
  });

  group('row tap', () {
    testWidgets('records a recent and pushes the Reader', (tester) async {
      final sample = FakeVaultProvider(files: {'Welcome.md': _bytes('# hi')});
      final vault = VaultState(
        sampleProvider: sample,
        folderProvider: FakeVaultProvider(),
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      expect(vault.recents, isEmpty);

      await tester.tap(find.text('Welcome.md'));
      await tester.pumpAndSettle();

      // The tap pushes the Reader with no pre-read; ReaderScreen._load's
      // own readDoc is what records the recent (the Library-side pre-read
      // was dropped — it doubled every open and swallowed read errors).
      expect(vault.recents.single.relPath, 'Welcome.md');
      // pushReader (navigation.dart) routes to the real ReaderScreen (Task
      // 5) — confirms the tap actually navigated, not just updated state.
      // The Reader's own parse call fails here (no FFI library reachable
      // under `flutter test` — see renderer.dart's doc comment) *after*
      // its readDoc recorded the recent, and ReaderScreen surfaces that as
      // its error state rather than crashing; the header (filename) still
      // renders regardless, which is what this test cares about.
      // (findsWidgets, not findsOneWidget: the Reader's bottom bar shows
      // the filename too as its no-doc section-label fallback, now as its
      // own exact Text since the label/percent split.)
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome.md'), findsWidgets);
    });
  });

  group('empty vault state', () {
    testWidgets('shows a "Choose folder" prompt when there is no grant', (
      tester,
    ) async {
      final vault = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: FakeVaultProvider(),
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      expect(find.text('No folder added'), findsOneWidget);
      expect(find.text('Choose folder'), findsOneWidget);
    });

    testWidgets('tapping "Choose folder" calls VaultState.pickFolder', (
      tester,
    ) async {
      final folder = FakeVaultProvider(
        pickResult: const VaultGrant(id: 'g1', displayName: 'Picked'),
        files: {'A.md': _bytes('a')},
      );
      final vault = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: folder,
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();

      expect(vault.vaultName, 'Picked');
      expect(find.text('PICKED'), findsOneWidget);
    });

    testWidgets(
      'a failed pick surfaces a dismissible banner instead of crashing',
      (tester) async {
        final folder = FakeVaultProvider(
          pickError: PlatformException(code: 'busy', message: 'busy'),
        );
        final vault = VaultState(
          sampleProvider: FakeVaultProvider(),
          folderProvider: folder,
        );
        await vault.init();

        await tester.pumpWidget(_wrap(vault));
        await tester.pump();

        await tester.tap(find.text('Choose folder'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Already choosing a folder'),
          findsOneWidget,
        );

        await tester.tap(find.text('✕'));
        await tester.pump();

        expect(find.textContaining('Already choosing a folder'), findsNothing);
      },
    );
  });

  group('search field', () {
    testWidgets('tapping it invokes onOpenSearch', (tester) async {
      var tapped = false;
      final vault = VaultState(
        sampleProvider: FakeVaultProvider(),
        folderProvider: FakeVaultProvider(),
      );
      await vault.init();

      await tester.pumpWidget(_wrap(vault, onOpenSearch: () => tapped = true));
      await tester.pump();

      await tester.tap(find.text('Search files and headings'));
      await tester.pump();

      expect(tapped, true);
    });
  });
}
