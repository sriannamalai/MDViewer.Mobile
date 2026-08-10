import 'package:flutter/foundation.dart';

import '../render/renderer.dart';
import '../render/scrollspy.dart';

/// Per-open-document reading state — design/README.md's "State management":
/// "activeDoc + per-doc scroll % and active heading". Owned by `ReaderScreen`
/// for the document it currently hosts (a fresh instance per push/replace,
/// not a singleton), and exposed down its subtree via `ChangeNotifierProvider
/// .value` so the bottom bar's "section · %" text, the progress hairline,
/// and — once Task 6 lands — the outline sheet's active-row highlight can
/// all read the same live state instead of each re-deriving it from raw
/// scrollspy messages.
class ReaderDocState extends ChangeNotifier {
  ReaderDocState({required this.model});

  final DocModel model;

  double _progress = 0;
  double get progress => _progress;

  int _activeLine = 0;
  int get activeLine => _activeLine;

  /// The outline entry currently active for [activeLine]: the item with the
  /// greatest `line` that is still `<= activeLine` (mirrors MDViewer.Desktop
  /// `outline.ts`'s `activeItemFor` — "the last heading the reader has
  /// scrolled past"), falling back to the first heading before any
  /// scrollspy message has landed. Null for a document with no headings.
  OutlineHeading? get activeHeading {
    OutlineHeading? best;
    for (final item in model.outline) {
      if (item.line <= _activeLine) best = item;
    }
    if (best != null) return best;
    return model.outline.isEmpty ? null : model.outline.first;
  }

  /// Applies a decoded `ScrollSpy` channel message. A no-op (no
  /// `notifyListeners`) when the payload doesn't actually change anything,
  /// since scroll messages arrive up to once per animation frame while the
  /// user is scrolling.
  void applyScrollSpy(ScrollSpyPayload payload) {
    if (payload.progress == _progress && payload.line == _activeLine) return;
    _progress = payload.progress;
    _activeLine = payload.line;
    notifyListeners();
  }
}
