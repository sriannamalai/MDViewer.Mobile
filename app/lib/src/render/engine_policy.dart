/// Engine policy for the reader: which rendering engine — the native
/// typed-tree pipeline or the legacy webview — a given document uses,
/// and the per-document prefs keys the decision (and the engine-neutral
/// reading position) persist under.
///
/// Pure Dart on purpose: nothing here touches widgets, the webview, or
/// the platform — the policy is unit-testable without fakes.
library;

import 'package:mdviewer/mdviewer.dart';

import '../vault/vault_source.dart';

/// The reader's rendering engine.
///
/// Wire strings (`'native'`/`'webview'`) are what [engineKey] entries
/// persist; [decode] sanitizes rather than throws (the app's
/// "sanitize never throws" prefs rule — see AppState/VaultState): any
/// unrecognized or missing value decodes to null, which callers treat
/// as "no override" so auto-detection applies.
enum ReaderEngine {
  native('native'),
  webview('webview');

  const ReaderEngine(this.wire);

  /// The persisted wire string for this engine.
  final String wire;

  /// Decodes a persisted wire string; null for anything unrecognized
  /// (corrupt blob, missing key, future value) — never a throw.
  static ReaderEngine? decode(String? raw) {
    for (final engine in values) {
      if (engine.wire == raw) return engine;
    }
    return null;
  }
}

/// Whether the tree contains at least one diagram addressed to the
/// `mermaid` engine — the auto-detection input to [resolveEngine]
/// (mermaid renders only on the webview engine until the offscreen-SVG
/// fast-follow).
///
/// Recursive over every container the version-1 schema nests blocks in:
/// blockQuote, admonition, list items ([MdvListItem] is not itself an
/// [MdvBlock] — its `blocks` are walked explicitly), definition lists
/// (descriptions carry blocks; terms are inline-only), footnote
/// definitions, and the envelope's [MdvTree.footnotes] array. Detection
/// is keyed on `engine == 'mermaid'`, not on the node type: a diagram
/// addressed to any other engine is not a hit. [MdvUnknownBlock] (the
/// forward-compat kind) is never a hit and never a throw.
bool treeContainsMermaid(MdvTree tree) =>
    tree.blocks.any(_blockContainsMermaid) ||
    tree.footnotes.any(_blockContainsMermaid);

bool _blockContainsMermaid(MdvBlock block) {
  // Exhaustive over the sealed union: a future MdvBlock kind added to
  // the model is a compile-time miss here, forcing this walk to decide
  // whether the new kind nests blocks.
  return switch (block) {
    MdvDiagram(:final engine) => engine == 'mermaid',
    MdvBlockQuote(:final blocks) => blocks.any(_blockContainsMermaid),
    MdvAdmonition(:final blocks) => blocks.any(_blockContainsMermaid),
    MdvList(:final items) => items.any(
      (item) => item.blocks.any(_blockContainsMermaid),
    ),
    MdvDefinitionList(:final blocks) => blocks.any(_blockContainsMermaid),
    MdvDefinitionDesc(:final blocks) => blocks.any(_blockContainsMermaid),
    MdvFootnoteDef(:final blocks) => blocks.any(_blockContainsMermaid),
    // Leaf blocks: no nested blocks anywhere. Tables nest only inline
    // cells; definition terms carry inlines only; a codeBlock fenced
    // `mermaid` that the parser did NOT lift into a diagram stays code.
    MdvHeading() ||
    MdvParagraph() ||
    MdvCodeBlock() ||
    MdvMathBlock() ||
    MdvTable() ||
    MdvThematicBreak() ||
    MdvHtmlBlock() ||
    MdvDefinitionTerm() ||
    MdvUnknownBlock() => false,
  };
}

/// Resolves the engine for a document. Precedence, exactly:
///
/// 1. [persistedOverride] — the user's per-document choice is absolute
///    in BOTH directions (an explicit `native` on a mermaid document
///    yields native; the diagrams degrade, by the user's own call).
/// 2. else [hasMermaid] → [ReaderEngine.webview].
/// 3. else [ReaderEngine.native].
ReaderEngine resolveEngine({
  required ReaderEngine? persistedOverride,
  required bool hasMermaid,
}) {
  if (persistedOverride != null) return persistedOverride;
  return hasMermaid ? ReaderEngine.webview : ReaderEngine.native;
}

// Per-document prefs keys. All three reader keys share one namespace
// shape, keyed by the entry's vault source and vault-relative path:
//
//   'reader.scroll.<source>:<relPath>'  — progress float (webview
//       restore; pre-existing, built inline in reader.dart as
//       'reader.scroll.${entry.source.name}:${entry.relPath}')
//   'reader.engine.<source>:<relPath>'  — ReaderEngine wire string
//       (the persisted override; absent = auto-detect)
//   'reader.line.<source>:<relPath>'    — engine-neutral top source
//       line (int; native restores by line, both engines write it)
//
// <source> is [VaultSource.name] (`sample`/`folder`/`openedFile`),
// matching the scroll key verbatim.

/// Prefs key for the document's persisted engine override.
String engineKey(VaultSource source, String relPath) =>
    'reader.engine.${source.name}:$relPath';

/// Prefs key for the document's engine-neutral top-line position.
String lineKey(VaultSource source, String relPath) =>
    'reader.line.${source.name}:$relPath';
