import 'package:flutter/material.dart';
import 'package:mdviewer/mdviewer.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../state/app_state.dart';

/// The native engine's document content — plugin 0.10.1's
/// [MdvDocumentAdapter] plugged into a [ScrollablePositionedList] (the
/// positioned-scrolling dependency lives in the APP, per the library
/// README's "Composing your own scrollable"). Swapped in for the
/// webview's [WebViewWidget] inside the otherwise-identical Reader
/// chrome; the Reader owns everything around it.
///
/// ## What this widget does and does not own
///
/// - The [tree] is built ONCE per document by the Reader
///   (`DocRenderer.renderTree`) and passed in — this widget never calls
///   into the FFI layer, and nothing here re-renders the document.
/// - The [itemScrollController]/[itemPositionsListener] are the Reader's
///   fields (created per document alongside the tree): outline jumps,
///   scrollspy, and position persistence plug into them Reader-side.
/// - The adapter is constructed PER BUILD — cheap by its contract (a key
///   table over the blocks), and deliberately so: `AppState.textScale`
///   feeds [MdvDocumentAdapter.baseStyle] and the ambient theme resolves
///   the (null) palette at item-build time, so an Aa step or theme flip
///   restyles in place with NO re-render and NO scroll reset (item
///   indices survive).
///
/// ## baseStyle contract
///
/// `TextStyle(fontSize: 16 * textScale)` and NOTHING else: the adapter
/// merges it OVER its default
/// `TextStyle(color: palette.foreground, fontSize: 16, height: 1.5)`,
/// so a fontSize-only override keeps the palette color and line height.
/// (16 is the adapter's own default body size — the native scale base —
/// not the webview CSS's 15px.)
///
/// ## findChildIndexCallback
///
/// `ScrollablePositionedList.builder` exposes no
/// `findChildIndexCallback`, so the adapter's key→index map goes
/// unrouted here: keys still ride every item's `KeyedSubtree`, but keyed
/// block STATE would not survive an index shift. Acceptable by design,
/// not an oversight: v2 renders one immutable tree per document (no
/// re-parse mid-view, ever), so indices never shift while a document is
/// on screen.
///
/// Padding: the host owns the scrollable's outer padding
/// (`EdgeInsets.fromLTRB(20, 22, 20, 22)`), mirroring the webview CSS's
/// `22px 20px` page padding.
class NativeDocView extends StatelessWidget {
  const NativeDocView({
    super.key,
    required this.tree,
    required this.itemScrollController,
    required this.itemPositionsListener,
    this.initialScrollIndex = 0,
    this.onLinkTap,
    this.imageProvider,
  });

  /// The document's typed render tree — built exactly once per document
  /// (Reader-side); immutable for this widget's whole lifetime.
  final MdvTree tree;

  /// Reader-owned scroll control (outline jump / restore-by-line).
  final ItemScrollController itemScrollController;

  /// Reader-owned position stream (scrollspy / persistence).
  final ItemPositionsListener itemPositionsListener;

  /// The item the list starts on — computed by the Reader BEFORE first
  /// paint (`NativeReaderScroll.initialScrollIndex` maps the persisted
  /// line / one-shot `initialLine` through `blockIndexForLine`), so a
  /// position restore lands as list construction, never a post-frame
  /// `jumpTo` flash of the document top. 0 (the default) is the top.
  final int initialScrollIndex;

  /// Link taps, routed to the Reader's nav policy; null renders links
  /// styled but inert (blocked links are always inert, plugin-side).
  final MdvLinkTapCallback? onLinkTap;

  /// Image resolution (`native_images.dart`'s `NativeImageResolver`).
  /// MUST be a long-lived object, not an inline closure: the plugin
  /// re-resolves whenever this compares unequal across builds.
  final MdvImageResolver? imageProvider;

  // Stateless by design: every field is host-owned (the Reader holds the
  // tree, controller/listener, resolver), and the per-build adapter is
  // the styling mechanism — there is nothing to keep in State. (Task 4's
  // scaffolding briefly made this a field-less StatefulWidget; flattened
  // per the ledger's routed minor once Task 5 confirmed no state
  // arrived.)
  @override
  Widget build(BuildContext context) {
    final textScale = context.watch<AppState>().textScale;
    final adapter = MdvDocumentAdapter(
      tree,
      // palette stays null: resolved from the ambient Theme's brightness
      // at item-build time, so a theme flip recolors without a new tree.
      baseStyle: TextStyle(fontSize: 16 * textScale),
      onLinkTap: onLinkTap,
      imageProvider: imageProvider,
      selectable: true,
    );
    return adapter.wrap(
      context,
      ScrollablePositionedList.builder(
        itemCount: adapter.itemCount,
        itemBuilder: adapter.itemBuilder,
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
        initialScrollIndex: initialScrollIndex,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      ),
    );
  }
}
