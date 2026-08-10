// OutlineSheet — design/README.md §03: rows per outline level/indent,
// the live active-row highlight following ReaderDocState's scrollspy
// state, tap-to-scroll-and-dismiss, the formatted header, and the empty
// state.

import 'package:app/src/render/renderer.dart';
import 'package:app/src/render/scrollspy.dart';
import 'package:app/src/screens/outline_sheet.dart';
import 'package:app/src/state/doc_state.dart';
import 'package:app/src/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const DocModel _fixtureModel = DocModel(
  outline: [
    OutlineHeading(level: 1, text: 'Overview', line: 1),
    OutlineHeading(level: 2, text: 'Status', line: 5),
    OutlineHeading(level: 2, text: 'Features', line: 9),
    OutlineHeading(level: 3, text: 'Rewriting links and images', line: 14),
    // A level beyond H3 — clamps to H3's indent/style (documented in
    // outline_sheet.dart's _OutlineRow doc comment).
    OutlineHeading(level: 4, text: 'Deeply nested', line: 20),
  ],
  words: 1140,
  readMinutes: 5,
);

/// Wraps [OutlineSheet.show] behind a button so tests can drive the real
/// `showModalBottomSheet` route (dismiss-on-tap, veil, animation) rather
/// than pumping [OutlineSheet] bodilessly outside a Navigator.
Widget _harness({
  required ReaderDocState docState,
  required ValueChanged<int> onTapHeading,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => OutlineSheet.show(
              context,
              docState: docState,
              onTapHeading: onTapHeading,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The row's own `Material` fill color (design/README.md §03: "active
/// section `accentSoft` fill") — the nearest `Material` ancestor of the
/// row's text, i.e. `_OutlineRow`'s own `Material`, not some outer one
/// (`find.ancestor` walks outward from the text, so `.first` is nearest).
Color? _rowFillColor(WidgetTester tester, String text) {
  return tester
      .widget<Material>(
        find
            .ancestor(of: find.text(text), matching: find.byType(Material))
            .first,
      )
      .color;
}

void main() {
  testWidgets('renders one row per outline entry, in document order', (
    tester,
  ) async {
    final docState = ReaderDocState(model: _fixtureModel);

    await tester.pumpWidget(_harness(docState: docState, onTapHeading: (_) {}));
    await _open(tester);

    for (final heading in _fixtureModel.outline) {
      expect(find.text(heading.text), findsOneWidget);
    }

    // Document order top-to-bottom: each row's y-offset increases in the
    // same order as the outline list.
    final ys = [
      for (final heading in _fixtureModel.outline)
        tester.getTopLeft(find.text(heading.text)).dy,
    ];
    expect(ys, orderedEquals(List.of(ys)..sort()));
  });

  testWidgets('indents by level: H1 < H2 < H3, and beyond-H3 clamps to H3', (
    tester,
  ) async {
    final docState = ReaderDocState(model: _fixtureModel);

    await tester.pumpWidget(_harness(docState: docState, onTapHeading: (_) {}));
    await _open(tester);

    final h1X = tester.getTopLeft(find.text('Overview')).dx;
    final h2X = tester.getTopLeft(find.text('Status')).dx;
    final h3X = tester.getTopLeft(find.text('Rewriting links and images')).dx;
    final beyondH3X = tester.getTopLeft(find.text('Deeply nested')).dx;

    expect(h1X, lessThan(h2X));
    expect(h2X, lessThan(h3X));
    // A level-4 heading renders at the exact same indent as H3 (clamped).
    expect(beyondH3X, h3X);
  });

  testWidgets("the sheet panel is painted on an outer decoration carrying the "
      "design's drop shadow (not clipped away by the content ClipRRect)", (
    tester,
  ) async {
    final docState = ReaderDocState(model: _fixtureModel);

    await tester.pumpWidget(_harness(docState: docState, onTapHeading: (_) {}));
    await _open(tester);

    final panel = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.boxShadow != null);

    expect(panel.color, AppTokens.light.panel);
    expect(
      panel.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(AppGeometry.sheetRadius),
      ),
    );
    final shadow = panel.boxShadow!.single;
    expect(shadow.color, AppOverlay.outlineSheetShadow);
    expect(
      shadow.offset,
      const Offset(0, AppGeometry.outlineSheetShadowOffsetY),
    );
    expect(shadow.blurRadius, AppGeometry.outlineSheetShadowBlurRadius);
  });

  testWidgets('header shows the word count grouped + read minutes', (
    tester,
  ) async {
    final docState = ReaderDocState(model: _fixtureModel);

    await tester.pumpWidget(_harness(docState: docState, onTapHeading: (_) {}));
    await _open(tester);

    expect(find.text('ON THIS PAGE'), findsOneWidget);
    expect(find.text('1,140 words · 5 min'), findsOneWidget);
  });

  testWidgets(
    'the active row (from ReaderDocState) is accent-colored and accentSoft-filled',
    (tester) async {
      final docState = ReaderDocState(model: _fixtureModel)
        ..applyScrollSpy(const ScrollSpyPayload(progress: 0.4, line: 9));

      await tester.pumpWidget(
        _harness(docState: docState, onTapHeading: (_) {}),
      );
      await _open(tester);

      expect(docState.activeHeading?.text, 'Features');

      final activeStyle = tester.widget<Text>(find.text('Features')).style!;
      expect(activeStyle.color, AppTokens.light.accent);
      expect(activeStyle.fontWeight, AppTypeScale.outlineRowActiveWeight);
      expect(_rowFillColor(tester, 'Features'), AppTokens.light.accentSoft);

      final inactiveStyle = tester.widget<Text>(find.text('Status')).style!;
      expect(inactiveStyle.color, isNot(AppTokens.light.accent));
      expect(_rowFillColor(tester, 'Status'), Colors.transparent);
    },
  );

  testWidgets(
    'the active-row highlight live-updates while the sheet stays open',
    (tester) async {
      final docState = ReaderDocState(model: _fixtureModel)
        ..applyScrollSpy(const ScrollSpyPayload(progress: 0.4, line: 9));

      await tester.pumpWidget(
        _harness(docState: docState, onTapHeading: (_) {}),
      );
      await _open(tester);

      expect(
        tester.widget<Text>(find.text('Features')).style!.color,
        AppTokens.light.accent,
      );

      // The scrollspy moves on while the sheet is still open — the sheet
      // is never given a snapshot, it's watching docState directly.
      docState.applyScrollSpy(const ScrollSpyPayload(progress: 0.6, line: 14));
      await tester.pump();

      expect(
        tester.widget<Text>(find.text('Features')).style!.color,
        isNot(AppTokens.light.accent),
      );
      expect(
        tester
            .widget<Text>(find.text('Rewriting links and images'))
            .style!
            .color,
        AppTokens.light.accent,
      );
    },
  );

  testWidgets(
    'tapping a row invokes the callback with its line and dismisses',
    (tester) async {
      final docState = ReaderDocState(model: _fixtureModel);
      int? tappedLine;

      await tester.pumpWidget(
        _harness(docState: docState, onTapHeading: (line) => tappedLine = line),
      );
      await _open(tester);
      expect(find.text('Status'), findsOneWidget);

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(tappedLine, 5);
      // Dismissed: the sheet's content is gone.
      expect(find.text('Status'), findsNothing);
      expect(find.text('ON THIS PAGE'), findsNothing);
    },
  );

  testWidgets('an empty outline shows the tokens-styled "No headings" state', (
    tester,
  ) async {
    final docState = ReaderDocState(model: DocModel.empty);

    await tester.pumpWidget(_harness(docState: docState, onTapHeading: (_) {}));
    await _open(tester);

    expect(find.text('No headings'), findsOneWidget);
    expect(find.text('0 words · 1 min'), findsOneWidget);
  });
}
