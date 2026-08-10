// SearchScreen widget tests (design/README.md §04): chip toggle
// active/inactive styling, the count line, results rendering with the
// match substring in `accent`, and tap -> Reader navigation carrying the
// matched line. Uses the same FakeVaultProvider/FakeWebViewPlatform pattern
// library_test.dart and reader_test.dart already established — device-free.

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/screens/reader.dart';
import 'package:app/src/screens/search.dart';
import 'package:app/src/state/app_state.dart';
import 'package:app/src/state/vault_state.dart';
import 'package:app/src/tokens.dart';
import 'package:app/src/vault/vault_entry.dart';
import 'package:app/src/vault/vault_grant.dart';
import 'package:app/src/vault/vault_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_webview_platform.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

class FakeVaultProvider implements VaultProvider {
  FakeVaultProvider({Map<String, Uint8List>? files}) : files = files ?? {};

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

Widget _wrap(VaultState vault, {bool autofocus = false}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>(create: (_) => AppState()),
      ChangeNotifierProvider<VaultState>.value(value: vault),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: SearchScreen(autofocus: autofocus),
    ),
  );
}

Future<VaultState> _vaultWith(Map<String, String> sampleFiles) async {
  final sample = FakeVaultProvider(
    files: sampleFiles.map((path, content) => MapEntry(path, _bytes(content))),
  );
  final vault = VaultState(
    sampleProvider: sample,
    folderProvider: FakeVaultProvider(),
  );
  await vault.init();
  return vault;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  testWidgets('shows an idle prompt before any query is typed', (tester) async {
    final vault = await _vaultWith({'A.md': 'hello world'});
    await tester.pumpWidget(_wrap(vault));
    await tester.pump();

    expect(find.textContaining('Search across your vault'), findsOneWidget);
  });

  testWidgets('typing a query (after the debounce) shows matching results', (
    tester,
  ) async {
    final vault = await _vaultWith({
      'README.md': 'Hosts that need a Resolver can supply one.',
    });
    await tester.pumpWidget(_wrap(vault));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'resolver');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('README.md'), findsOneWidget);
    expect(find.textContaining('1 result in 1 file'), findsOneWidget);
  });

  testWidgets('the matched substring renders in the accent color', (
    tester,
  ) async {
    final vault = await _vaultWith({
      'README.md': 'Hosts that need a Resolver can supply one.',
    });
    await tester.pumpWidget(_wrap(vault));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Resolver');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // Distinguish the snippet's RichText from the query TextField's own
    // internal RichText (which also contains the plain text "Resolver" —
    // it's what the user just typed) by matching on the full snippet
    // sentence rather than just the match substring.
    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((w) => w.text.toPlainText().contains('Hosts that need'));
    // Text.rich(span, style: s) wraps the given span one level deep
    // (RichText(text: TextSpan(style: s, children: [span]))), so the
    // highlighted spans this widget built are the wrapper's own children.
    final outer = richText.text as TextSpan;
    final wrapper = outer.children!.single as TextSpan;
    final spans = wrapper.children!.cast<TextSpan>();
    final matchSpan = spans.firstWhere((s) => s.text == 'Resolver');

    expect(matchSpan.style?.color, AppTokens.light.accent);
  });

  testWidgets('an unmatched query shows "No results"', (tester) async {
    final vault = await _vaultWith({'README.md': 'nothing relevant here'});
    await tester.pumpWidget(_wrap(vault));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz-not-present');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('an invalid regex pattern shows an inline error, not a crash', (
    tester,
  ) async {
    final vault = await _vaultWith({'README.md': 'anything'});
    await tester.pumpWidget(_wrap(vault));
    await tester.pump();

    // Toggle the ".*" (regex) chip on.
    await tester.tap(find.text('.*'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '(unclosed');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Invalid pattern'), findsOneWidget);
  });

  group('filter chips', () {
    testWidgets('Aa toggles between inactive (text3) and active (accent)', (
      tester,
    ) async {
      final vault = await _vaultWith({'A.md': 'x'});
      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      Text aaText() => tester.widget<Text>(find.text('Aa'));
      expect(aaText().style?.color, AppTokens.light.text3);

      await tester.tap(find.text('Aa'));
      await tester.pump();

      expect(aaText().style?.color, AppTokens.light.accent);
    });

    testWidgets(
      'toggling a chip re-runs the search immediately (no debounce)',
      (tester) async {
        final vault = await _vaultWith({'A.md': 'Cat and cat and CAT'});
        await tester.pumpWidget(_wrap(vault));
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'cat');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.textContaining('3 results'), findsOneWidget);

        await tester.tap(find.text('Aa')); // case-sensitive on
        // No debounce delay for a chip toggle, but the search is still
        // async internally (VaultSearch.search yields once per file via a
        // Future.delayed(Duration.zero)) — a bare pump() doesn't elapse
        // fake time at all, so it needs an explicit duration to fire.
        await tester.pump(const Duration(milliseconds: 1));

        expect(find.textContaining('1 result in 1 file'), findsOneWidget);
      },
    );
  });

  group('result tap', () {
    testWidgets('records a recent and pushes the Reader at the matched line', (
      tester,
    ) async {
      final vault = await _vaultWith({
        'README.md': 'line one\nline two\nfind the target here\n',
      });
      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'target');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(vault.recents, isEmpty);

      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();

      expect(vault.recents.single.relPath, 'README.md');
      expect(tester.takeException(), isNull);

      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(reader.entry.relPath, 'README.md');
      expect(reader.initialLine, 3);
    });
  });

  group('autofocus', () {
    testWidgets('requests focus when autofocus is true', (tester) async {
      final vault = await _vaultWith({'A.md': 'x'});
      await tester.pumpWidget(_wrap(vault, autofocus: true));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, true);
    });

    testWidgets('does not request focus when autofocus is false', (
      tester,
    ) async {
      final vault = await _vaultWith({'A.md': 'x'});
      await tester.pumpWidget(_wrap(vault));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, false);
    });
  });
}
