import 'package:flutter/material.dart';

import '../render/renderer.dart';
import '../state/doc_state.dart';
import '../tokens.dart';
import '../util/thousands.dart';

/// The Outline sheet — design/README.md §03: a modal bottom sheet over the
/// Reader listing every heading in the current document ("On this page"),
/// with the row for the section currently being read highlighted, and a
/// tap on any row jumping the Reader there and dismissing.
///
/// Presented via [OutlineSheet.show], which owns the sheet chrome
/// (`showModalBottomSheet`'s veil/shape/motion) design/README.md §03 and
/// §Interactions specify: veil `rgba(10,11,12,.28)`
/// ([AppOverlay.outlineVeil]), sheet radius 18 top corners
/// ([AppGeometry.sheetRadius]), ~300ms spring-ish entrance
/// ([AppGeometry.outlineSheetDuration] + [AppGeometry.motionPanelCurve]),
/// and native drag-to-dismiss/veil-tap-dismiss (`showModalBottomSheet`'s
/// `enableDrag`/`isDismissible` defaults — no custom gesture code needed).
///
/// Subscribes to [docState] directly (a [ListenableBuilder], not a
/// snapshot of `docState.activeHeading` taken once at open time) so the
/// active row keeps following the scrollspy while the sheet stays open —
/// the brief's "live-updating while the sheet is open" requirement. The
/// Reader keeps rendering underneath (unpaused), so its own scroll
/// listener keeps feeding [docState] scrollspy messages the whole time.
class OutlineSheet extends StatelessWidget {
  const OutlineSheet({
    super.key,
    required this.docState,
    required this.onTapHeading,
  });

  final ReaderDocState docState;

  /// Invoked with the tapped heading's source line — the Reader's caller
  /// wires this to `__mdvScrollToLine` (scrollspy.dart's
  /// `scrollToLineScript`). The sheet dismisses itself right after calling
  /// this ("Tap scrolls and dismisses" is a single atomic action owned by
  /// the sheet, not split across caller/callee).
  final ValueChanged<int> onTapHeading;

  /// A sheet's content is capped to this fraction of the screen height so a
  /// long document's outline scrolls internally instead of overflowing —
  /// an implementation choice (the design reference is a single static
  /// mockup with 8 rows, no scroll-cap spec), not a design token.
  static const double _maxHeightFraction = 0.72;

  /// Presents the sheet over [context]'s current route.
  static Future<void> show(
    BuildContext context, {
    required ReaderDocState docState,
    required ValueChanged<int> onTapHeading,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppOverlay.outlineVeil,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        duration: AppGeometry.outlineSheetDuration,
        curve: AppGeometry.motionPanelCurve,
      ),
      builder: (_) =>
          OutlineSheet(docState: docState, onTapHeading: onTapHeading),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * _maxHeightFraction;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppGeometry.sheetRadius),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(color: tokens.panel),
          child: Padding(
            padding: EdgeInsets.only(
              top: AppGeometry.sheetTopPadding,
              left: AppGeometry.outlineSheetHorizontalPadding,
              right: AppGeometry.outlineSheetHorizontalPadding,
              bottom: AppGeometry.outlineSheetBottomPaddingMin + bottomInset,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Grabber(color: tokens.line),
                _Header(model: docState.model),
                Flexible(
                  child: docState.model.outline.isEmpty
                      ? const _EmptyState()
                      : ListenableBuilder(
                          listenable: docState,
                          builder: (context, _) => _OutlineRows(
                            outline: docState.model.outline,
                            activeLine: docState.activeHeading?.line,
                            onTapHeading: (line) {
                              onTapHeading(line);
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 40×4 radius-2 drag handle centered above the header — design/
/// README.md §03: "40×4 grabber `line` centered".
class _Grabber extends StatelessWidget {
  const _Grabber({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppGeometry.outlineGrabberWidth,
      height: AppGeometry.outlineGrabberHeight,
      margin: const EdgeInsets.only(
        bottom: AppGeometry.outlineGrabberBottomMargin,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppGeometry.outlineGrabberRadius),
      ),
    );
  }
}

/// "On this page" (uppercase, left) + "N words · M min" (mono, right) —
/// design/README.md §03's header row.
class _Header extends StatelessWidget {
  const _Header({required this.model});

  final DocModel model;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGeometry.outlineHeaderHorizontalPadding,
        0,
        AppGeometry.outlineHeaderHorizontalPadding,
        AppGeometry.outlineHeaderBottomPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'On this page'.toUpperCase(),
            style: TextStyle(
              fontFamily: AppFonts.ibmPlexSans,
              fontSize: AppTypeScale.outlineHeaderLabelSize,
              fontWeight: AppTypeScale.outlineHeaderLabelWeight,
              letterSpacing: AppTypeScale.outlineHeaderLabelLetterSpacing,
              color: tokens.text3,
            ),
          ),
          Text(
            '${Thousands.format(model.words)} words · ${model.readMinutes} min',
            style: TextStyle(
              fontFamily: AppFonts.jetBrainsMono,
              fontSize: AppTypeScale.outlineHeaderMetaSize,
              color: tokens.text3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The scrollable list of heading rows, re-built whenever the active line
/// changes (the [ListenableBuilder] in [OutlineSheet.build] re-invokes
/// this widget's constructor on every scrollspy update, not just once at
/// open).
class _OutlineRows extends StatelessWidget {
  const _OutlineRows({
    required this.outline,
    required this.activeLine,
    required this.onTapHeading,
  });

  final List<OutlineHeading> outline;
  final int? activeLine;
  final ValueChanged<int> onTapHeading;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppGeometry.outlineRowsHorizontalPadding,
      ),
      shrinkWrap: true,
      itemCount: outline.length,
      itemBuilder: (context, index) {
        final heading = outline[index];
        return _OutlineRow(
          heading: heading,
          active: heading.line == activeLine,
          onTap: () => onTapHeading(heading.line),
        );
      },
    );
  }
}

/// One heading row — design/README.md §03: "44px, radius 10, 15px text;
/// H1 500 `text2`, H2 indent 28px, H3 indent 42px `text3`; active section
/// `accentSoft` fill + `accent`/600." Levels beyond H3 clamp to H3's
/// indent/style (the brief's documented behavior for a level this design
/// never anticipated — headings deeper than H3 are rare in practice, and
/// visually indistinguishable past that depth is preferable to indenting
/// off the sheet's edge).
class _OutlineRow extends StatelessWidget {
  const _OutlineRow({
    required this.heading,
    required this.active,
    required this.onTap,
  });

  final OutlineHeading heading;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final level = heading.level.clamp(1, 3);

    final double leftPadding = switch (level) {
      1 => AppGeometry.outlineIndentH1,
      2 => AppGeometry.outlineIndentH2,
      _ => AppGeometry.outlineIndentH3,
    };

    final TextStyle style = active
        ? TextStyle(
            fontFamily: AppFonts.ibmPlexSans,
            fontSize: AppTypeScale.outlineRowTextSize,
            fontWeight: AppTypeScale.outlineRowActiveWeight,
            color: tokens.accent,
          )
        : TextStyle(
            fontFamily: AppFonts.ibmPlexSans,
            fontSize: AppTypeScale.outlineRowTextSize,
            fontWeight: level == 1
                ? AppTypeScale.outlineRowH1Weight
                : AppTypeScale.outlineRowInactiveWeight,
            color: level == 3 ? tokens.text3 : tokens.text2,
          );

    return Material(
      color: active ? tokens.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppGeometry.radiusOutlineRow),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppGeometry.radiusOutlineRow),
        highlightColor: tokens.panel2,
        splashColor: tokens.panel2,
        child: Container(
          height: AppGeometry.rowHeightMin,
          padding: EdgeInsets.only(
            left: leftPadding,
            right: AppGeometry.outlineRowPaddingRight,
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            heading.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ),
    );
  }
}

/// A document with no headings at all — design/README.md §03 has no spec
/// for this case (its mockup always shows a populated outline), so this is
/// a minimal tokens-styled placeholder rather than an invented design:
/// centered, tertiary-colored text, no icon/illustration.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'No headings',
          style: TextStyle(
            fontFamily: AppFonts.ibmPlexSans,
            fontSize: AppTypeScale.uiTextSize,
            color: tokens.text3,
          ),
        ),
      ),
    );
  }
}
