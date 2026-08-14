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
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
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
  _FakeDocRenderer({this.headingText = 'Hello'});

  /// The fixture's single H1 text — overridable so tests can exercise the
  /// bottom bar's long-section-label ellipsis behavior.
  final String headingText;

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
            {'kind': 'text', 'value': headingText},
          ],
        },
        {
          'kind': 'paragraph',
          'span': {'startLine': 3},
          'children': [
            {'kind': 'text', 'value': 'one two three'},
            // Exercises DocImages.prefetch + the re-render image-reuse
            // regression: only resolves when the test's vault actually
            // holds img/x.png; harmlessly skipped everywhere else.
            {'kind': 'image', 'destination': 'img/x.png'},
          ],
        },
      ],
    };
  }

  /// The resolver the most recent [render] call received — lets tests
  /// assert a re-render still carries the images prefetched at load time.
  MdvResolver? lastResolver;

  @override
  String render(
    Object doc, {
    required Brightness brightness,
    required double textScale,
    MdvResolver? resolver,
  }) {
    renderCalls++;
    lastResolver = resolver;
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

Future<VaultState> _vaultWith(
  VaultEntry entry,
  String markdown, {
  Map<String, Uint8List> extraFiles = const {},
}) async {
  final provider = _FakeVaultProvider(
    files: {entry.relPath: _bytes(markdown), ...extraFiles},
  );
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

  testWidgets('registers the CodeCopy channel and injects its bridge script', (
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
    // Channel registered alongside ScrollSpy in the controller setup.
    expect(controller.channels.keys, containsAll(['ScrollSpy', 'CodeCopy']));
    // Both injected scripts land in the loaded page, each before the
    // real </body> (splice discipline is unit-tested in
    // codecopy_test.dart/scrollspy_test.dart against a mermaid decoy).
    final html = controller.loadedHtml!;
    expect(html, contains('window.CodeCopy'));
    final bodyClose = html.lastIndexOf('</body>');
    expect(html.indexOf('window.CodeCopy'), lessThan(bodyClose));
    expect(html.indexOf('ScrollSpy'), lessThan(bodyClose));
  });

  testWidgets(
    'a CodeCopy message writes the posted code text to the system clipboard',
    (tester) async {
      // The test binding's platform-channel mock: Clipboard.setData goes
      // over SystemChannels.platform, so capture its MethodCalls.
      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final entry = _sampleEntry();
      final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
      final appState = AppState();
      await appState.init();
      final renderer = _FakeDocRenderer();

      await tester.pumpWidget(
        _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
      );
      await tester.pumpAndSettle();

      const snippet = 'func main() {\n\tfmt.Println("hi")\n}\n';
      platform.controllers.single.simulateMessage('CodeCopy', snippet);
      await tester.pump();

      final copies = platformCalls.where(
        (c) => c.method == 'Clipboard.setData',
      );
      expect(copies, hasLength(1));
      expect(
        (copies.single.arguments as Map)['text'],
        snippet,
        reason: 'the message body IS the code text, verbatim — not JSON',
      );
    },
  );

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
    // The section label and the ' · N%' are two separate Texts (only the
    // label may ellipsize — see _BottomBar).
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text(' · 0%'), findsOneWidget);

    final controller = platform.controllers.single;
    controller.simulateMessage('ScrollSpy', '{"p": 0.42, "h": 1}');
    await tester.pump();

    expect(find.text(' · 42%'), findsOneWidget);

    // The painted fill, not just the label: the accent bar must actually
    // have the hairline's full height and 42% of its width. (Regression:
    // a FractionallySizedBox without heightFactor collapsed the fill to
    // zero height — track visible, fill invisible, found on-device.)
    final fillFinder = find.descendant(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(ColoredBox),
    );
    expect(fillFinder, findsOneWidget);
    final fillSize = tester.getSize(fillFinder);
    final trackSize = tester.getSize(
      // .first = the nearest ColoredBox ancestor (the line2 track); further
      // ancestors (screen background etc.) also match the type.
      find
          .ancestor(
            of: find.byType(FractionallySizedBox),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(fillSize.height, trackSize.height);
    expect(fillSize.height, greaterThan(0));
    expect(
      fillSize.width,
      moreOrLessEquals(trackSize.width * 0.42, epsilon: 1),
    );
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
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text(' · 0%'), findsOneWidget);
  });

  testWidgets('the bottom bar percent survives a long section label', (
    tester,
  ) async {
    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
    final appState = AppState();
    await appState.init();
    // Far wider than any phone: with the old single
    // '$sectionLabel · $percent%' Text, tail ellipsis swallowed the
    // percent entirely (found on-device).
    final renderer = _FakeDocRenderer(
      headingText:
          'An extremely long section heading that cannot possibly '
          'fit in the bottom bar next to the Outline pill and Aa button '
          'without being ellipsized somewhere along the way',
    );

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    // The percent is its own (never-ellipsized) Text, so it must render
    // with real width no matter how long the section label is.
    expect(find.text(' · 0%'), findsOneWidget);
    expect(tester.getSize(find.text(' · 0%')).width, greaterThan(0));
  });

  testWidgets('navigation policy (Android): nothing navigates — '
      'data:/mailto:/tel:/about: are all explicitly declined', (tester) async {
    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
    final appState = AppState();
    await appState.init();
    final renderer = _FakeDocRenderer();

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    final decide =
        platform.controllers.single.navigationDelegate!.onNavigationRequest!;
    Future<NavigationDecision> decision(String url) async =>
        await decide(NavigationRequest(url: url, isMainFrame: true));

    // A data: request reaching the delegate is always a tapped link (the
    // API-initiated load never routes through it here) — declined, so a
    // `[open](data:text/html;base64,...)` doc link can't replace the
    // rendered document with link-authored HTML.
    expect(await decision('data:text/html,x'), NavigationDecision.prevent);
    // Explicit declines — a fall-through navigate here replaced the
    // document with a blank page on Android (Task 8 on-device finding).
    expect(await decision('mailto:a@b.c'), NavigationDecision.prevent);
    expect(await decision('tel:+15551234567'), NavigationDecision.prevent);
    // Tests run as TargetPlatform.android by default: about:* is a
    // collapsed relative-link tap there, never an API-initiated load.
    expect(await decision('about:blank'), NavigationDecision.prevent);
    // External links: prevented in the WebView (handed to the OS browser).
    expect(await decision('https://example.com'), NavigationDecision.prevent);
    // Internal relative links: prevented in the WebView (routed in-app).
    expect(await decision('Other.md'), NavigationDecision.prevent);
  });

  testWidgets('navigation policy (iOS): only the API load\'s own about:blank '
      'navigates; other about:* and data: are declined', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // Safety net if an expect throws mid-test (keeps later tests clean);
    // the happy path must reset before the body ends — the binding checks
    // foundation debug variables before tearDowns run.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final entry = _sampleEntry();
    final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
    final appState = AppState();
    await appState.init();
    final renderer = _FakeDocRenderer();

    await tester.pumpWidget(
      _wrap(vault, appState, ReaderScreen(entry: entry, renderer: renderer)),
    );
    await tester.pumpAndSettle();

    final decide =
        platform.controllers.single.navigationDelegate!.onNavigationRequest!;
    Future<NavigationDecision> decision(String url) async =>
        await decide(NavigationRequest(url: url, isMainFrame: true));

    // WKWebView surfaces loadHtmlString's own load as exactly about:blank.
    expect(await decision('about:blank'), NavigationDecision.navigate);
    // Any other about:* is a tapped doc link, not the API load — declined.
    expect(await decision('about:config'), NavigationDecision.prevent);
    // data: reaching the delegate is a tapped link on iOS too — declined.
    expect(await decision('data:text/html,x'), NavigationDecision.prevent);
    // The scheme-empty relative .md branch behaves the same as on Android:
    // prevented in the WebView (routed in-app).
    expect(await decision('Other.md'), NavigationDecision.prevent);

    debugDefaultTargetPlatformOverride = null;
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

  testWidgets(
    'initialLine scrolls to the given line once the page finishes loading',
    (tester) async {
      final entry = _sampleEntry();
      final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
      final appState = AppState();
      await appState.init();
      final renderer = _FakeDocRenderer();

      await tester.pumpWidget(
        _wrap(
          vault,
          appState,
          ReaderScreen(entry: entry, renderer: renderer, initialLine: 7),
        ),
      );
      await tester.pumpAndSettle();

      final controller = platform.controllers.single;
      expect(controller.executedScripts, isEmpty);

      controller.navigationDelegate?.onPageFinished?.call('about:blank');
      await tester.pump();

      expect(
        controller.executedScripts,
        contains(contains('__mdvScrollToLine && window.__mdvScrollToLine(7)')),
      );
    },
  );

  testWidgets(
    'initialLine takes priority over restoring a persisted scroll % — a '
    'search-result jump must not be clobbered by a stale position',
    (tester) async {
      final entry = _sampleEntry();
      SharedPreferences.setMockInitialValues({
        // A persisted scroll position from a previous read — must NOT win
        // over the search-result line this load was explicitly asked for.
        'reader.scroll.sample:Welcome.md': 0.5,
      });
      final vault = await _vaultWith(entry, '# Hello\n\none two three\n');
      final appState = AppState();
      await appState.init();
      final renderer = _FakeDocRenderer();

      await tester.pumpWidget(
        _wrap(
          vault,
          appState,
          ReaderScreen(entry: entry, renderer: renderer, initialLine: 3),
        ),
      );
      await tester.pumpAndSettle();

      final controller = platform.controllers.single;
      controller.navigationDelegate?.onPageFinished?.call('about:blank');
      await tester.pump();

      expect(
        controller.executedScripts,
        contains(contains('__mdvScrollToLine && window.__mdvScrollToLine(3)')),
      );
      expect(
        controller.executedScripts.any(
          (s) => s.contains('__mdvScrollToProgress'),
        ),
        false,
        reason:
            'the persisted 0.5 restore must be skipped entirely once an '
            'initialLine jump has fired for this load',
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
    // (findsWidgets: the bottom bar also shows the filename as its no-doc
    // section-label fallback, its own exact Text since the label/percent
    // split.)
    expect(find.text('Welcome.md'), findsWidgets);
  });

  testWidgets(
    'the Aa button opens a bottom sheet that re-renders at the new scale',
    (tester) async {
      final entry = _sampleEntry();
      final vault = await _vaultWith(
        entry,
        '# Hello\n\none two three\n',
        extraFiles: {
          'img/x.png': Uint8List.fromList([1, 2, 3]),
        },
      );
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

      // The re-render must still resolve the image prefetched at load —
      // regression: _renderInto used to fall back to DocImages.empty on
      // re-render, so the second render's resolver dropped every relative
      // image (found on-device in Task 8's E2E).
      final resolved = renderer.lastResolver!(
        MdvResolveKind.image,
        'img/x.png',
      );
      expect(resolved, isNotNull);
      expect(resolved, startsWith('data:image/png;base64,'));
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

  testWidgets(
    'a scrollspy message ALSO persists the engine-neutral line key alongside '
    'the progress float (the native engine restores by that line)',
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

      final controller = platform.controllers.single;
      controller.simulateMessage('ScrollSpy', '{"p": 0.4, "h": 7}');
      await tester.pump();
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      // The pre-existing per-message float write is byte-for-byte
      // unchanged (cadence included)…
      expect(prefs.getDouble('reader.scroll.sample:Welcome.md'), 0.4);
      // …and the payload's line now rides alongside it under the
      // engine-neutral key — the ONLY webview-path change this train
      // makes.
      expect(prefs.getInt('reader.line.sample:Welcome.md'), 7);
    },
  );
}
