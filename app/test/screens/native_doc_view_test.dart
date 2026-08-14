import 'package:app/src/render/native_images.dart';
import 'package:app/src/screens/native_doc_view.dart';
import 'package:app/src/state/app_state.dart';
import 'package:app/src/tokens.dart';
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
  const _Host({required this.tree});

  final MdvTree tree;

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
    );
  }
}

/// App shell around the host: providers + MaterialApp with a mutable
/// [ThemeMode] so tests can flip the ambient brightness live.
class _Shell extends StatefulWidget {
  const _Shell({required this.appState, required this.tree});

  final AppState appState;
  final MdvTree tree;

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
        home: Scaffold(body: _Host(tree: widget.tree)),
      ),
    );
  }
}

Future<AppState> _appState() async {
  final appState = AppState();
  await appState.init();
  return appState;
}

Future<void> _pump(WidgetTester tester, AppState appState, MdvTree tree) async {
  await tester.pumpWidget(_Shell(appState: appState, tree: tree));
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
}
