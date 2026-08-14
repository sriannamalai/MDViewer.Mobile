import 'dart:async';

import 'package:app/src/render/native_images.dart';
import 'package:app/src/render/renderer.dart';
import 'package:app/src/screens/native_doc_view.dart';
import 'package:app/src/screens/reader.dart';
import 'package:app/src/state/app_state.dart';
import 'package:app/src/state/doc_state.dart';
import 'package:app/src/tokens.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_tree.dart';

/// Hosts a [NativeDocView] the way the Reader will (plan Task 4/5): the
/// scroll controller/listener and the image resolver are STATE FIELDS
/// created once, never per-build values — [poke] rebuilds via `setState`
/// so tests can assert what survives a rebuild unchanged.
class _Host extends StatefulWidget {
  const _Host({required this.tree, this.palette});

  final MdvTree tree;

  /// The loaded palette the Reader hands down (native_palette.dart);
  /// null keeps the adapter's ambient-brightness default.
  final MdvPalette? palette;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final ItemScrollController scrollController = ItemScrollController();
  final ItemPositionsListener positionsListener =
      ItemPositionsListener.create();

  /// Held as a field, mirroring the Reader's contract: the plugin
  /// re-resolves every image whenever this callback compares unequal
  /// across builds, and an inline closure per build always would.
  late final MdvImageResolver resolver = NativeImageResolver(
    resolveBytes: (_) async => null,
  ).call;

  int rebuilds = 0;

  void poke() => setState(() => rebuilds++);

  @override
  Widget build(BuildContext context) {
    return NativeDocView(
      tree: widget.tree,
      itemScrollController: scrollController,
      itemPositionsListener: positionsListener,
      imageProvider: resolver,
      palette: widget.palette,
    );
  }
}

/// App shell around the host: providers + MaterialApp with a mutable
/// [ThemeMode] so tests can flip the ambient brightness live.
class _Shell extends StatefulWidget {
  const _Shell({required this.appState, required this.tree, this.palette});

  final AppState appState;
  final MdvTree tree;
  final MdvPalette? palette;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  ThemeMode mode = ThemeMode.light;

  void setMode(ThemeMode next) => setState(() => mode = next);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: widget.appState,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Scaffold(
          body: _Host(tree: widget.tree, palette: widget.palette),
        ),
      ),
    );
  }
}

Future<AppState> _appState() async {
  final appState = AppState();
  await appState.init();
  return appState;
}

Future<void> _pump(
  WidgetTester tester,
  AppState appState,
  MdvTree tree, {
  MdvPalette? palette,
}) async {
  await tester.pumpWidget(
    _Shell(appState: appState, tree: tree, palette: palette),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the tree blocks inside a positioned list with the '
      'reader page padding', (tester) async {
    final appState = await _appState();
    await _pump(tester, appState, fakeTree());

    expect(find.text(fakeTreeHeadingText), findsOneWidget);
    expect(find.text(fakeTreeParagraphText), findsOneWidget);

    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(list.itemCount, 3);
    // Host-owned page padding, mirroring the webview CSS's 22px/20px.
    expect(list.padding, const EdgeInsets.fromLTRB(20, 22, 20, 22));
    // The adapter's document shell: selectable content over the palette
    // background.
    expect(
      find.descendant(
        of: find.byType(NativeDocView),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders an MdvTree.fromMap-decoded tree identically '
      '(fixture drift guard)', (tester) async {
    final appState = await _appState();
    await _pump(tester, appState, fakeTreeFromWireMap());

    expect(find.text(fakeTreeHeadingText), findsOneWidget);
    expect(find.text(fakeTreeParagraphText), findsOneWidget);
    expect(
      tester
          .widget<ScrollablePositionedList>(
            find.byType(ScrollablePositionedList),
          )
          .itemCount,
      3,
    );
  });

  testWidgets('baseStyle scales ONLY fontSize (16 × textScale); palette '
      'color and line height survive the merge', (tester) async {
    final appState = await _appState();
    await appState.setTextScale(1.15);
    await _pump(tester, appState, fakeTree());

    // The adapter's wrap() DefaultTextStyle — outermost inside the view.
    final style = tester
        .widget<DefaultTextStyle>(
          find
              .descendant(
                of: find.byType(NativeDocView),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style;

    expect(style.fontSize, closeTo(16 * 1.15, 1e-9)); // 18.4
    expect(
      style.color,
      MdvPalette.light.foreground,
      reason: 'a fontSize-only baseStyle must keep the palette color',
    );
    expect(
      style.height,
      1.5,
      reason: 'a fontSize-only baseStyle must keep the default line height',
    );
  });

  testWidgets('an Aa step restyles in place — same tree instance, new '
      'fontSize, no new document', (tester) async {
    final appState = await _appState();
    final tree = fakeTree();
    await _pump(tester, appState, tree);

    TextStyle styleNow() => tester
        .widget<DefaultTextStyle>(
          find
              .descendant(
                of: find.byType(NativeDocView),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style;

    expect(styleNow().fontSize, closeTo(16.0, 1e-9));

    await appState.setTextScale(1.3);
    await tester.pumpAndSettle();

    expect(styleNow().fontSize, closeTo(16 * 1.3, 1e-9));
    final view = tester.widget<NativeDocView>(find.byType(NativeDocView));
    expect(
      identical(view.tree, tree),
      isTrue,
      reason: 'text scale feeds baseStyle at build time — never a new tree',
    );
  });

  testWidgets('ambient theme flip re-colors via the palette without a new '
      'tree', (tester) async {
    final appState = await _appState();
    final tree = fakeTree();
    await _pump(tester, appState, tree);

    Color background() => (tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(NativeDocView),
            matching: find.byType(ColoredBox),
          )
          .first,
    )).color;

    expect(background(), MdvPalette.light.background);

    tester.state<_ShellState>(find.byType(_Shell)).setMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(background(), MdvPalette.dark.background);
    final view = tester.widget<NativeDocView>(find.byType(NativeDocView));
    expect(
      identical(view.tree, tree),
      isTrue,
      reason:
          'a null palette resolves from the ambient theme at build '
          'time — never a new tree',
    );
  });

  testWidgets('the image resolver is the SAME callback object across '
      'rebuilds (the plugin memoizes on callback identity)', (tester) async {
    final appState = await _appState();
    await _pump(tester, appState, fakeTree());

    final before = tester
        .widget<NativeDocView>(find.byType(NativeDocView))
        .imageProvider;

    tester.state<_HostState>(find.byType(_Host)).poke();
    await tester.pumpAndSettle();

    final after = tester
        .widget<NativeDocView>(find.byType(NativeDocView))
        .imageProvider;

    expect(
      identical(before, after),
      isTrue,
      reason:
          'a per-build inline closure would refetch every image on '
          'every rebuild — the resolver must be a long-lived field',
    );
    // The comparison the plugin actually performs is ==; identity implies
    // it, but pin the operative contract too.
    expect(before == after, isTrue);
  });

  testWidgets('a code block carries the plugin copy button (no CodeCopy '
      'bridge on the native path)', (tester) async {
    final appState = await _appState();
    await _pump(tester, appState, fakeTree());

    expect(find.byType(MdvCopyButton), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  // ── Syntax-highlight palette (Task 7's on-device finding): the
  // adapter's baked-in default palettes carry page colors but an EMPTY
  // tokenColors map, so a null palette renders every code fence flat
  // while the webview engine highlights it. The Reader now hands down a
  // LOADED palette (native_palette.dart).

  testWidgets('a null palette leaves code token runs UNCOLORED — the '
      'regression this fixture pins', (tester) async {
    final appState = await _appState();
    await _pump(tester, appState, fakeCodeRunsTree());

    expect(
      _codeRunColor(tester, fakeCodeRunKeywordText),
      MdvPalette.light.foreground,
      reason:
          'MdvPalette.light has no tokenColors, so every token falls '
          'back to foreground — flat, unhighlighted code',
    );
  });

  testWidgets('a loaded palette colors code token runs by chroma token '
      'type', (tester) async {
    const keyword = Color(0xFFCF222E);
    final appState = await _appState();
    await _pump(
      tester,
      appState,
      fakeCodeRunsTree(),
      palette: MdvPalette.light.copyWith(
        tokenColors: const {fakeCodeRunTokenType: keyword},
      ),
    );

    expect(_codeRunColor(tester, fakeCodeRunKeywordText), keyword);
  });

  testWidgets('the palette is a build-time input: swapping it restyles in '
      'place, same tree instance', (tester) async {
    const light = Color(0xFFCF222E);
    const dark = Color(0xFFFF7B72);
    final appState = await _appState();
    final tree = fakeCodeRunsTree();
    await _pump(
      tester,
      appState,
      tree,
      palette: MdvPalette.light.copyWith(
        tokenColors: const {fakeCodeRunTokenType: light},
      ),
    );
    expect(_codeRunColor(tester, fakeCodeRunKeywordText), light);

    // What a theme flip does Reader-side: re-pick from the cached pair.
    await tester.pumpWidget(
      _Shell(
        appState: appState,
        tree: tree,
        palette: MdvPalette.dark.copyWith(
          tokenColors: const {fakeCodeRunTokenType: dark},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_codeRunColor(tester, fakeCodeRunKeywordText), dark);
    expect(
      identical(
        tester.widget<NativeDocView>(find.byType(NativeDocView)).tree,
        tree,
      ),
      isTrue,
      reason: 'a palette swap must never rebuild the document',
    );
  });

  // ── NativeReaderScroll (plan Task 4): the Reader-side scroll plumbing,
  // exercised here against the REAL ScrollablePositionedList in the test
  // viewport (the Reader's engine integration that wires it in is Task 5).

  testWidgets('outline tap: scrollToLine maps the line through '
      'blockIndexForLine (nearest preceding block) and lands on that '
      'block', (tester) async {
    final appState = await _appState();
    final tree = fakeLongTree();
    final docState = ReaderDocState(model: DocModel.empty);
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: docState,
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
    );
    await _pumpScrollHost(tester, appState, tree, scroll);

    // Deep enough that the target item is not even built yet.
    expect(find.text(fakeLongTreeParagraphText(30)), findsNothing);

    // One line PAST block 30's start line: the gap line between blocks
    // resolves to the nearest preceding block — same rule as the
    // webview's __mdvScrollToLine fallback.
    unawaited(scroll.scrollToLine(fakeLongTreeStartLine(30) + 1));
    await tester.pumpAndSettle();

    expect(find.text(fakeLongTreeParagraphText(30)), findsOneWidget);
    final target = scroll.itemPositionsListener.itemPositions.value.singleWhere(
      (position) => position.index == 30,
    );
    expect(
      target.itemLeadingEdge,
      closeTo(0, 0.01),
      reason: 'the animated scroll aligns the mapped block to the top',
    );

    scroll.dispose();
  });

  testWidgets('scrollToLine guards: a detached controller and an unmapped '
      'line are both no-ops', (tester) async {
    final appState = await _appState();
    final tree = fakeLongTree();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: ReaderDocState(model: DocModel.empty),
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
    );

    // Not attached to any list yet: returns without throwing.
    await scroll.scrollToLine(5);

    await _pumpScrollHost(tester, appState, tree, scroll);

    // Line 0 precedes every block: blockIndexForLine → null → no scroll.
    unawaited(scroll.scrollToLine(0));
    await tester.pumpAndSettle();

    expect(_topmostVisibleIndex(scroll), 0);
    expect(tester.takeException(), isNull);

    scroll.dispose();
  });

  testWidgets('initial position: a persisted line maps to its block index '
      'BEFORE first paint (initialScrollIndex, no post-frame jump)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reader.line.sample:Long.md': fakeLongTreeStartLine(30),
    });
    final appState = await _appState();
    final tree = fakeLongTree();
    final docState = ReaderDocState(model: DocModel.empty);
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: docState,
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
    );

    final prefs = await SharedPreferences.getInstance();
    final persisted = NativeReaderScroll.persistedLine(
      prefs,
      'reader.line.sample:Long.md',
    );
    expect(persisted, fakeLongTreeStartLine(30));

    final index = scroll.initialScrollIndex(
      initialLine: null,
      persistedLine: persisted,
    );
    expect(index, 30);

    await _pumpScrollHost(
      tester,
      appState,
      tree,
      scroll,
      initialScrollIndex: index,
    );

    expect(find.text(fakeLongTreeParagraphText(30)), findsOneWidget);
    final target = scroll.itemPositionsListener.itemPositions.value.singleWhere(
      (position) => position.index == 30,
    );
    expect(target.itemLeadingEdge, closeTo(0, 0.01));

    scroll.dispose();
  });

  testWidgets('initial position: a one-shot initialLine beats the persisted '
      'line for this load', (tester) async {
    SharedPreferences.setMockInitialValues({
      'reader.line.sample:Long.md': fakeLongTreeStartLine(30),
    });
    final appState = await _appState();
    final tree = fakeLongTree();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: ReaderDocState(model: DocModel.empty),
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
    );

    final prefs = await SharedPreferences.getInstance();
    final index = scroll.initialScrollIndex(
      initialLine: fakeLongTreeStartLine(12),
      persistedLine: NativeReaderScroll.persistedLine(
        prefs,
        'reader.line.sample:Long.md',
      ),
    );
    expect(index, 12, reason: 'a search-result jump wins over the restore');

    await _pumpScrollHost(
      tester,
      appState,
      tree,
      scroll,
      initialScrollIndex: index,
    );

    expect(find.text(fakeLongTreeParagraphText(12)), findsOneWidget);
    final target = scroll.itemPositionsListener.itemPositions.value.singleWhere(
      (position) => position.index == 12,
    );
    expect(target.itemLeadingEdge, closeTo(0, 0.01));

    scroll.dispose();
  });

  testWidgets('legacy float-only prefs start at top: the progress float is '
      'NEVER misread as a line, a corrupt line value degrades to null, '
      'and an unmappable line degrades to index 0', (tester) async {
    SharedPreferences.setMockInitialValues({
      // A v1 install: only the webview progress float exists.
      'reader.scroll.sample:Long.md': 0.77,
      // A corrupt line key: a double where an int belongs.
      'reader.line.sample:Corrupt.md': 0.5,
    });
    final appState = await _appState();
    final tree = fakeLongTree();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: ReaderDocState(model: DocModel.empty),
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      NativeReaderScroll.persistedLine(prefs, 'reader.line.sample:Long.md'),
      isNull,
      reason: 'absent line key: the 0.77 float must not be read as a line',
    );
    expect(
      NativeReaderScroll.persistedLine(prefs, 'reader.line.sample:Corrupt.md'),
      isNull,
      reason: 'a non-int value under the line key degrades to null',
    );

    expect(
      scroll.initialScrollIndex(initialLine: null, persistedLine: null),
      0,
    );
    // A line no block precedes (the webview writes h:0 before any heading
    // has scrolled past): blockIndexForLine → null → top.
    expect(scroll.initialScrollIndex(initialLine: null, persistedLine: 0), 0);

    await _pumpScrollHost(tester, appState, tree, scroll);

    expect(_topmostVisibleIndex(scroll), 0);
    expect(find.text(fakeLongTreeHeadingText), findsOneWidget);
    expect(tester.takeException(), isNull);

    scroll.dispose();
  });

  testWidgets('item positions drive docState: topmost visible is the MIN '
      'index with itemTrailingEdge > 0 — top padding offsets and '
      'scrolled-past items never pick the wrong block', (tester) async {
    final tree = fakeLongTree(paragraphs: 9); // itemCount 10
    final docState = ReaderDocState(model: DocModel.empty);
    final listener = _DrivenPositionsListener();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: docState,
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
      positionsListener: listener,
      persist: (_, _) async {},
    );

    // Pre-layout frame: no positions → a no-op, not a crash. Driven
    // with a FRESH empty list, not `const []`: the listener's
    // ValueNotifier seeds with a const empty list, and an identical
    // value skips notification entirely — only a distinct instance
    // actually runs the empty-positions guard under test.
    listener.drive(<ItemPosition>[]);
    expect(docState.progress, 0);
    expect(docState.activeLine, 0);

    // At the very top the 22px page padding puts item 0's leading edge
    // BELOW the viewport top (positive) — a naive `leadingEdge >= 0 is
    // the topmost` rule survives here, so pin the real rule's output:
    // item 0 topmost, progress exactly 0.
    listener.drive(const [
      ItemPosition(index: 0, itemLeadingEdge: 0.036, itemTrailingEdge: 0.2),
      ItemPosition(index: 1, itemLeadingEdge: 0.2, itemTrailingEdge: 0.5),
    ]);
    expect(docState.activeLine, fakeLongTreeStartLine(0));
    expect(docState.progress, 0);

    // Mid-document: item 3 fully scrolled past (trailing edge <= 0) is
    // EXCLUDED; item 4, a quarter scrolled past, is the topmost.
    listener.drive(const [
      ItemPosition(index: 3, itemLeadingEdge: -0.4, itemTrailingEdge: 0.0),
      ItemPosition(index: 4, itemLeadingEdge: -0.25, itemTrailingEdge: 0.75),
      ItemPosition(index: 5, itemLeadingEdge: 0.75, itemTrailingEdge: 1.1),
    ]);
    expect(docState.activeLine, fakeLongTreeStartLine(4));
    // (index 4 + 0.25 of it consumed) / 10 items.
    expect(docState.progress, closeTo(0.425, 1e-9));

    // An empty positions frame mid-flight keeps the last state.
    listener.drive(const []);
    expect(docState.activeLine, fakeLongTreeStartLine(4));
    expect(docState.progress, closeTo(0.425, 1e-9));

    scroll.dispose();
  });

  testWidgets('the trailing footnotes item holds the last line (null line '
      'mapping) while progress keeps approaching 1', (tester) async {
    final tree = fakeLongTreeWithFootnotes(paragraphs: 8); // itemCount 10
    final docState = ReaderDocState(model: DocModel.empty);
    final listener = _DrivenPositionsListener();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: docState,
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
      positionsListener: listener,
      persist: (_, _) async {},
    );

    // Reading the last body block…
    listener.drive(const [
      ItemPosition(index: 8, itemLeadingEdge: -0.1, itemTrailingEdge: 0.6),
      ItemPosition(index: 9, itemLeadingEdge: 0.6, itemTrailingEdge: 1.2),
    ]);
    expect(docState.activeLine, fakeLongTreeStartLine(8));

    // …then the footnotes item (index 9 = blocks.length) becomes topmost:
    // startLineForIndex → null → the line HOLDS; progress keeps going
    // (its bottom edge still below the viewport: no snap yet).
    listener.drive(const [
      ItemPosition(index: 9, itemLeadingEdge: -0.6, itemTrailingEdge: 1.2),
    ]);
    expect(
      docState.activeLine,
      fakeLongTreeStartLine(8),
      reason: 'a null line mapping keeps the last known line',
    );
    expect(docState.progress, closeTo((9 + 0.6 / 1.8) / 10, 1e-9));
    expect(docState.progress, greaterThan(0.9));

    // …and once the last item's bottom edge reaches the viewport
    // (itemTrailingEdge <= 1) progress SNAPS to exactly 1.0 — parity
    // with the webview's exact-1.0 at its scroll end; the line still
    // holds.
    listener.drive(const [
      ItemPosition(index: 9, itemLeadingEdge: -0.8, itemTrailingEdge: 1.0),
    ]);
    expect(docState.activeLine, fakeLongTreeStartLine(8));
    expect(docState.progress, 1.0);

    scroll.dispose();
  });

  testWidgets('progress snaps to exactly 1.0 whenever the last item is '
      'fully visible — the block-weighted value alone would cap below 1.0 '
      'when the tail fits in the viewport', (tester) async {
    final tree = fakeLongTree(paragraphs: 9); // itemCount 10
    final docState = ReaderDocState(model: DocModel.empty);
    final listener = _DrivenPositionsListener();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: docState,
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
      positionsListener: listener,
      persist: (_, _) async {},
    );

    // The last two items on screen, the final one ending above the
    // viewport bottom: block-weighted progress would be
    // (8 + 0.2/0.6)/10 ≈ 0.83 — but the document end is fully visible,
    // which IS the webview's progress==1.0 scroll-end.
    listener.drive(const [
      ItemPosition(index: 8, itemLeadingEdge: -0.2, itemTrailingEdge: 0.4),
      ItemPosition(index: 9, itemLeadingEdge: 0.4, itemTrailingEdge: 0.95),
    ]);
    expect(docState.activeLine, fakeLongTreeStartLine(8));
    expect(docState.progress, 1.0);

    scroll.dispose();
  });

  testWidgets('an empty tree (itemCount 0) and a zero-extent position are '
      'no-ops — never a divide-by-zero', (tester) async {
    const empty = MdvTree(version: 1, blocks: [], footnotes: []);
    final emptyDocState = ReaderDocState(model: DocModel.empty);
    final emptyListener = _DrivenPositionsListener();
    final emptyScroll = NativeReaderScroll(
      tree: empty,
      docState: emptyDocState,
      progressKey: 'reader.scroll.sample:Empty.md',
      lineKey: 'reader.line.sample:Empty.md',
      positionsListener: emptyListener,
      persist: (_, _) async {},
    );
    // A position report against an empty tree (cannot happen through the
    // real list, but the guard must hold): ignored.
    emptyListener.drive(const [
      ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.1),
    ]);
    expect(emptyDocState.progress, 0);
    expect(emptyDocState.activeLine, 0);
    emptyScroll.dispose();

    // itemCount 1 with a zero-extent position (trailing == leading):
    // the consumed-fraction division is guarded (no throw). The single
    // item is BOTH the first and the last, with both edges on screen —
    // the document does not scroll, and the bottom snap is gated on
    // that, so progress stays the block-weighted 0. Webview parity: an
    // unscrollable document reports 0 there too (scrollY never leaves
    // 0), and 100%-at-first-paint would also write a bogus 1.0 to the
    // shared `reader.scroll.…` restore key.
    final one = fakeLongTree(paragraphs: 0);
    final oneDocState = ReaderDocState(model: DocModel.empty);
    final oneListener = _DrivenPositionsListener();
    final oneScroll = NativeReaderScroll(
      tree: one,
      docState: oneDocState,
      progressKey: 'reader.scroll.sample:One.md',
      lineKey: 'reader.line.sample:One.md',
      positionsListener: oneListener,
      persist: (_, _) async {},
    );
    oneListener.drive(const [
      ItemPosition(index: 0, itemLeadingEdge: 0.3, itemTrailingEdge: 0.3),
    ]);
    expect(oneDocState.activeLine, fakeLongTreeStartLine(0));
    expect(oneDocState.progress, 0);
    expect(tester.takeException(), isNull);
    oneScroll.dispose();
  });

  testWidgets('a multi-item document that fits ENTIRELY in the viewport '
      'reports its block-weighted value (0 at rest), not the bottom '
      'snap — the webview reports 0 on an unscrollable document', (
    tester,
  ) async {
    final tree = fakeLongTree(paragraphs: 2); // itemCount 3
    final docState = ReaderDocState(model: DocModel.empty);
    final listener = _DrivenPositionsListener();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: docState,
      progressKey: 'reader.scroll.sample:Short.md',
      lineKey: 'reader.line.sample:Short.md',
      positionsListener: listener,
      persist: (_, _) async {},
    );

    // Every item on screen at once: item 0's leading edge at the
    // viewport top AND the last item's trailing edge above its bottom.
    // The list cannot move, so this IS the top of the document.
    listener.drive(const [
      ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.2),
      ItemPosition(index: 1, itemLeadingEdge: 0.2, itemTrailingEdge: 0.4),
      ItemPosition(index: 2, itemLeadingEdge: 0.4, itemTrailingEdge: 0.6),
    ]);
    expect(docState.activeLine, fakeLongTreeStartLine(0));
    expect(
      docState.progress,
      0,
      reason:
          'a document that never scrolls must not open at 100% — '
          'the webview reports 0 (scrollY stays 0), and the snap would '
          'also persist a bogus 1.0 under the shared restore key',
    );

    scroll.dispose();
  });

  testWidgets('persistence is throttled to one write per 500ms carrying the '
      'LATEST value; dispose flushes the pending value and cancels the '
      'timer', (tester) async {
    final tree = fakeLongTree(paragraphs: 9);
    final writes = <(double, int)>[];
    final listener = _DrivenPositionsListener();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: ReaderDocState(model: DocModel.empty),
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
      positionsListener: listener,
      persist: (progress, line) async => writes.add((progress, line)),
    );

    // Two updates inside the 500ms window…
    listener.drive(const [
      ItemPosition(index: 2, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
    ]);
    listener.drive(const [
      ItemPosition(index: 5, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
    ]);
    expect(writes, isEmpty, reason: 'nothing is written inside the window');

    await tester.pump(const Duration(milliseconds: 499));
    expect(writes, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));

    // …collapse to ONE write carrying the latest value.
    expect(writes, hasLength(1));
    expect(writes.single.$1, closeTo(0.5, 1e-9));
    expect(writes.single.$2, fakeLongTreeStartLine(5));

    // A further update, then dispose before the window elapses: the
    // pending value is flushed (backgrounded/killed right after
    // scrolling must not lose the position) and the timer is cancelled
    // (the test binding fails on any timer left pending).
    listener.drive(const [
      ItemPosition(index: 7, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
    ]);
    scroll.dispose();
    await tester.pump();

    expect(writes, hasLength(2));
    expect(writes.last.$2, fakeLongTreeStartLine(7));
  });

  testWidgets('the native persist path writes BOTH the progress float and '
      'the engine-neutral line key', (tester) async {
    final tree = fakeLongTree(paragraphs: 9);
    final listener = _DrivenPositionsListener();
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: ReaderDocState(model: DocModel.empty),
      progressKey: 'reader.scroll.sample:Long.md',
      lineKey: 'reader.line.sample:Long.md',
      positionsListener: listener,
    );

    listener.drive(const [
      ItemPosition(index: 4, itemLeadingEdge: -0.25, itemTrailingEdge: 0.75),
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('reader.scroll.sample:Long.md'),
      closeTo(0.425, 1e-9),
    );
    expect(
      prefs.getInt('reader.line.sample:Long.md'),
      fakeLongTreeStartLine(4),
    );

    scroll.dispose();
  });
}

/// [ItemPositionsListener] the tests drive by hand — exact edge values
/// for the padding/exclusion/footnotes cases without fighting real
/// scroll physics (the real-list tests above cover the wired path).
class _DrivenPositionsListener implements ItemPositionsListener {
  final ValueNotifier<Iterable<ItemPosition>> _positions = ValueNotifier(
    const <ItemPosition>[],
  );

  @override
  ValueListenable<Iterable<ItemPosition>> get itemPositions => _positions;

  void drive(Iterable<ItemPosition> positions) => _positions.value = positions;
}

/// Pumps a [NativeDocView] wired the way Task 5's Reader will wire it:
/// the [NativeReaderScroll]'s controller/listener pair plus the
/// pre-paint [initialScrollIndex].
Future<void> _pumpScrollHost(
  WidgetTester tester,
  AppState appState,
  MdvTree tree,
  NativeReaderScroll scroll, {
  int initialScrollIndex = 0,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: NativeDocView(
            tree: tree,
            itemScrollController: scroll.itemScrollController,
            itemPositionsListener: scroll.itemPositionsListener,
            initialScrollIndex: initialScrollIndex,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The color the rendered code block paints the token run whose text is
/// [runText] — walks the `Text.rich` span tree the plugin's code-block
/// view builds (one child [TextSpan] per [MdvTokenRun]).
Color? _codeRunColor(WidgetTester tester, String runText) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    Color? found;
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == runText) {
        found = span.style?.color;
        return false;
      }
      return true;
    });
    if (found != null) return found;
  }
  fail('no rendered code token run with text "$runText"');
}

/// The min index with `itemTrailingEdge > 0` — the same topmost-visible
/// rule NativeReaderScroll applies, read from the real list's positions.
int _topmostVisibleIndex(NativeReaderScroll scroll) {
  final visible = scroll.itemPositionsListener.itemPositions.value
      .where((position) => position.itemTrailingEdge > 0)
      .map((position) => position.index)
      .toList();
  expect(visible, isNotEmpty);
  return visible.reduce((a, b) => a < b ? a : b);
}
