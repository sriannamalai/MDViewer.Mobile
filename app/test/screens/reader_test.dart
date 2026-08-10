import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/render/renderer.dart';
import 'package:app/src/screens/reader.dart';
import 'package:app/src/state/app_state.dart';
import 'package:app/src/state/vault_state.dart';
import 'package:app/src/tokens.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_grant.dart';
import 'package:app/src/vault/vault_provider.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_webview_platform.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// Same device-free fake `vault_state_test.dart` uses.
class _FakeVaultProvider implements VaultProvider {
  _FakeVaultProvider({Map<String, Uint8List>? files}) : files = files ?? {};
  final Map<String, Uint8List> files;

  @override
  Future<VaultGrant?> pickFolder() async => null;

  @override
  Future<bool> restore(VaultGrant grant) async => true;

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

/// Bypasses the real FFI call entirely (see renderer.dart's [DocRenderer]
/// doc comment: `Mdviewer.instance` only resolves on a real device/
/// simulator/host — not under this app's `flutter test`), so widget tests
/// can exercise a *loaded* Reader deterministically and fast.
class _FakeDocRenderer extends DocRenderer {
  int renderCalls = 0;
  Object? throwOnParse;

  @override
  Map<String, dynamic> parse(String markdown) {
    if (throwOnParse != null) throw throwOnParse!;
    return {
      'version': 1,
      'kind': 'document',
      'children': [
        {
          'kind': 'heading',
          'level': 1,
          'span': {'startLine': 1},
          'children': [
            {'kind': 'text', 'value': 'Hello'},
          ],
        },
        {
          'kind': 'paragraph',
          'span': {'startLine': 3},
          'children': [
            {'kind': 'text', 'value': 'one two three'},
          ],
        },
      ],
    };
  }

  @override
  String render(
    Object doc, {
    required Brightness brightness,
    required double textScale,
    MdvResolver? resolver,
  }) {
    renderCalls++;
    return '<html><body><h1 data-md-line="1">Hello</h1></body></html>';
  }
}

VaultEntry _sampleEntry({String relPath = 'Welcome.md'}) => VaultEntry(
  name: relPath,
  relPath: relPath,
  isDir: false,
  children: const [],
  source: VaultSource.sample,
);

Future<VaultState> _vaultWith(VaultEntry entry, String markdown) async {
  final provider = _FakeVaultProvider(files: {entry.relPath: _bytes(markdown)});
  final vault = VaultState(
    sampleProvider: provider,
    folderProvider: _FakeVaultProvider(),
  );
  await vault.init();
  return vault;
}

Widget _wrap(VaultState vault, AppState appState, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VaultState>.value(value: vault),
      ChangeNotifierProvider<AppState>.value(value: appState),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebViewPlatform platform;

  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('loads, renders once, shows filename + vault·minutes meta', (
    tester,
  ) async {
    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
    final appState = AppState();
    await appState.init();
    final renderer = _FakeDocRenderer();

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome.md'), findsOneWidget);
    expect(find.textContaining('Samples · 1 min'), findsOneWidget);
    expect(renderer.renderCalls, 1);

    final controller = platform.controllers.single;
    expect(controller.loadedHtml, contains('data-md-line="1"'));
    expect(controller.loadedHtml, contains('ScrollSpy'));
  });

  testWidgets('a scrollspy message updates the hairline and section·%', (
    tester,
  ) async {
    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
    final appState = AppState();
    await appState.init();
    final renderer = _FakeDocRenderer();

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    // Before any scrollspy message: falls back to the first heading, 0%.
    expect(find.textContaining('Hello · 0%'), findsOneWidget);

    final controller = platform.controllers.single;
    controller.simulateMessage('ScrollSpy', '{"p": 0.42, "h": 1}');
    await tester.pump();

    expect(find.textContaining('Hello · 42%'), findsOneWidget);
  });

  testWidgets('a garbage scrollspy message is ignored, not a crash', (
    tester,
  ) async {
    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
    final appState = AppState();
    await appState.init();
    final renderer = _FakeDocRenderer();

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    final controller = platform.controllers.single;
    controller.simulateMessage('ScrollSpy', 'not json at all {{{');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Hello · 0%'), findsOneWidget);
  });

  testWidgets(
    'restores a persisted scroll position once the page finishes loading',
    (tester) async {
      final entry = _sampleEntry();
      SharedPreferences.setMockInitialValues({
        'reader.scroll.sample:Welcome.md': 0.77,
      });
      final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
      final appState = AppState();
      await appState.init();
      final renderer = _FakeDocRenderer();

      await tester.pumpWidget(
        _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
      );
      await tester.pumpAndSettle();

      final controller = platform.controllers.single;
      expect(controller.executedScripts, isEmpty);

      controller.navigationDelegate?.onPageFinished?.call('about:blank');
      await tester.pump();

      expect(
        controller.executedScripts,
        contains(contains('__mdvScrollToProgress(0.77)')),
      );
    },
  );

  testWidgets('scroll progress is persisted on every scrollspy update', (
    tester,
  ) async {
    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
    final appState = AppState();
    await appState.init();
    final renderer = _FakeDocRenderer();

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    final controller = platform.controllers.single;
    controller.simulateMessage('ScrollSpy', '{"p": 0.33, "h": 1}');
    await tester.pump();
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('reader.scroll.sample:Welcome.md'), 0.33);
  });

  testWidgets('a render failure shows an error state instead of crashing', (
    tester,
  ) async {
    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n');
    final appState = AppState();
    await appState.init();
    final renderer = _FakeDocRenderer()
      ..throwOnParse = StateError('boom: parse failed');

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining("Couldn't render this document"),
      findsOneWidget,
    );
    expect(find.textContaining('boom: parse failed'), findsOneWidget);
    // The header (back/share/filename) still works even in the error state.
    expect(find.text('Welcome.md'), findsOneWidget);
  });

  testWidgets(
    'the Aa button opens a bottom sheet that re-renders at the new scale',
    (tester) async {
      final entry = _sampleEntry();
      final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
      final appState = AppState();
      await appState.init();
      final renderer = _FakeDocRenderer();

      await tester.pumpWidget(
        _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
      );
      await tester.pumpAndSettle();
      expect(renderer.renderCalls, 1);

      await tester.tap(find.text('Aa'));
      await tester.pumpAndSettle();

      // AppState.defaultTextScale is 1.0 (100%) before stepping.
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      expect(find.text('115%'), findsOneWidget);
      expect(renderer.renderCalls, 2);
    },
  );

  testWidgets(
    'the Outline pill opens the Outline sheet, wired to __mdvScrollToLine',
    (tester) async {
      final entry = _sampleEntry();
      final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
      final appState = AppState();
      await appState.init();
      final renderer = _FakeDocRenderer();

      await tester.pumpWidget(
        _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The fixture's heading "Hello" + paragraph "one two three" is 4
      // words total (DocModel.analyze counts every text node, headings
      // included); the sheet's header shows that alongside the 1 words · 1
      // min floor.
      expect(find.text('4 words · 1 min'), findsOneWidget);

      await tester.tap(find.text('Hello').last);
      await tester.pumpAndSettle();

      final controller = platform.controllers.single;
      expect(
        controller.executedScripts,
        contains(contains('__mdvScrollToLine(1)')),
      );
      // Tap dismisses: the sheet's word-count header is gone again.
      expect(find.text('4 words · 1 min'), findsNothing);
    },
  );
}
