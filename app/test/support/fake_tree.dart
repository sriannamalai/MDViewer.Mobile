/// Shared canned [MdvTree] fixtures for native-engine tests
/// (`native_doc_view_test.dart` now; the Reader's native-path tests in
/// later tasks) — the typed-tree analogue of `reader_test.dart`'s
/// `_FakeDocRenderer` parse fixture.
///
/// Two builders on purpose (the fake-tree-vs-real-parse trap, pinned at
/// the fixture level): [fakeTree] is hand-built from the typed
/// constructors, and [fakeTreeFromWireMap] decodes the SAME document
/// through [MdvTree.fromMap] on a canned version-1 wire map — so a
/// hand-built fixture that drifts from the real decode shape shows up as
/// the two trees disagreeing under the same test, not as a green suite
/// over an impossible tree. (Real-FFI trees are covered by the device
/// E2E task; `flutter test` on a host cannot reach the native library —
/// see renderer.dart's [DocRenderer] doc comment.)
library;

import 'dart:ui' show Brightness;

import 'package:app/src/render/renderer.dart';
import 'package:mdviewer/mdviewer.dart';

/// Heading text of the canned document's single H1.
const String fakeTreeHeadingText = 'Native heading';

/// The canned paragraph's full text.
const String fakeTreeParagraphText = 'native body text';

/// The canned code block's literal source.
const String fakeTreeCodeText = 'void main() {}';

/// Hand-built typed tree: H1 + paragraph + dart code block, all with
/// real 1-based spans (`blockIndexForLine`/`startLineForIndex` need
/// them). Ids are arbitrary but unique (the adapter keys by
/// `(id, occurrence)`).
MdvTree fakeTree() => const MdvTree(
  version: 1,
  blocks: [
    MdvHeading(
      id: 'fixture-h1',
      span: MdvSpan(startLine: 1, endLine: 1, startOffset: 0, endOffset: 16),
      level: 1,
      anchorId: 'native-heading',
      children: [MdvText(value: fakeTreeHeadingText)],
    ),
    MdvParagraph(
      id: 'fixture-p1',
      span: MdvSpan(startLine: 3, endLine: 3, startOffset: 18, endOffset: 34),
      children: [MdvText(value: fakeTreeParagraphText)],
    ),
    MdvCodeBlock(
      id: 'fixture-c1',
      span: MdvSpan(startLine: 5, endLine: 7, startOffset: 36, endOffset: 61),
      language: 'dart',
      label: 'dart',
      runs: null,
      text: fakeTreeCodeText,
    ),
  ],
  footnotes: [],
);

/// The same document as [fakeTree], as a version-1 render-tree wire map
/// (the shape `Mdviewer.renderTreeDocRaw` returns — same field spelling
/// `engine_policy_test.dart`'s wire fixture uses). Returned fresh per
/// call so a test may mutate its copy.
Map<String, dynamic> fakeTreeWireMap() => <String, dynamic>{
  'version': 1,
  'blocks': [
    {
      'kind': 'heading',
      'id': 'fixture-h1',
      'span': {'startLine': 1, 'endLine': 1, 'startOffset': 0, 'endOffset': 16},
      'level': 1,
      'anchorId': 'native-heading',
      'children': [
        {'kind': 'text', 'value': fakeTreeHeadingText},
      ],
    },
    {
      'kind': 'paragraph',
      'id': 'fixture-p1',
      'span': {
        'startLine': 3,
        'endLine': 3,
        'startOffset': 18,
        'endOffset': 34,
      },
      'children': [
        {'kind': 'text', 'value': fakeTreeParagraphText},
      ],
    },
    {
      'kind': 'codeBlock',
      'id': 'fixture-c1',
      'span': {
        'startLine': 5,
        'endLine': 7,
        'startOffset': 36,
        'endOffset': 61,
      },
      'language': 'dart',
      'label': 'dart',
      'runs': null,
      'text': fakeTreeCodeText,
    },
  ],
  'footnotes': <dynamic>[],
};

/// [fakeTreeWireMap] decoded through the REAL [MdvTree.fromMap] — the
/// drift guard: a structural mistake in the wire fixture throws here
/// (strict decode), and tests running over this tree exercise exactly
/// what a decoded tree carries.
MdvTree fakeTreeFromWireMap() => MdvTree.fromMap(fakeTreeWireMap());

/// Heading text of [fakeLongTree]'s H1 (block 0, line 1).
const String fakeLongTreeHeadingText = 'Long native heading';

/// The text of [fakeLongTree]'s paragraph at [blockIndex] (1-based over
/// blocks — block 0 is the H1).
String fakeLongTreeParagraphText(int blockIndex) =>
    'Scroll paragraph $blockIndex — filler prose long enough to give the '
    'block real height in a test viewport.';

/// The 1-based source line block [blockIndex] of [fakeLongTree] starts
/// on: blocks sit two lines apart (1, 3, 5, …), so every inter-block
/// gap line exists for nearest-preceding-block mapping tests.
int fakeLongTreeStartLine(int blockIndex) => 1 + 2 * blockIndex;

/// A long scrollable document: an H1 (line 1) followed by [paragraphs]
/// paragraphs at lines 3, 5, 7, … — enough vertical extent that a test
/// viewport (800×600 default surface) genuinely scrolls. Spans follow
/// [fakeLongTreeStartLine]; ids are unique per block.
MdvTree fakeLongTree({int paragraphs = 39}) => MdvTree(
  version: 1,
  blocks: [
    const MdvHeading(
      id: 'long-h1',
      span: MdvSpan(startLine: 1, endLine: 1, startOffset: 0, endOffset: 19),
      level: 1,
      anchorId: 'long-native-heading',
      children: [MdvText(value: fakeLongTreeHeadingText)],
    ),
    for (var i = 1; i <= paragraphs; i++)
      MdvParagraph(
        id: 'long-p$i',
        span: MdvSpan(
          startLine: fakeLongTreeStartLine(i),
          endLine: fakeLongTreeStartLine(i),
          startOffset: 0,
          endOffset: 0,
        ),
        children: [MdvText(value: fakeLongTreeParagraphText(i))],
      ),
  ],
  footnotes: const [],
);

/// The token type [fakeCodeRunsTree]'s first run carries — a real
/// chroma name, the key shape `highlight-*.json` uses.
const String fakeCodeRunTokenType = 'Keyword';

/// The literal text of [fakeCodeRunsTree]'s first (keyword) run.
const String fakeCodeRunKeywordText = 'void';

/// A one-block document whose code fence carries SYNTAX-HIGHLIGHT TOKEN
/// RUNS (what `renderTreeDoc` really produces — highlighting is on by
/// default in the tree builder). [fakeTree]'s code block deliberately
/// has `runs: null`; this fixture is the other half, so the palette's
/// `tokenColors` have something to color (Task 7's on-device finding:
/// the adapter's baked-in default palettes carry NO token colors).
MdvTree fakeCodeRunsTree() => const MdvTree(
  version: 1,
  blocks: [
    MdvCodeBlock(
      id: 'fixture-runs-c1',
      span: MdvSpan(startLine: 1, endLine: 3, startOffset: 0, endOffset: 25),
      language: 'dart',
      label: 'dart',
      runs: [
        MdvTokenRun(text: fakeCodeRunKeywordText, tokenType: 'Keyword'),
        MdvTokenRun(text: ' main() {}', tokenType: 'Text'),
      ],
      text: '$fakeCodeRunKeywordText main() {}',
    ),
  ],
  footnotes: [],
);

/// [fakeTree] plus a trailing mermaid diagram block — the
/// `treeContainsMermaid` auto-webview trigger for engine-policy reader
/// tests.
MdvTree fakeMermaidTree() => MdvTree(
  version: 1,
  blocks: [
    ...fakeTree().blocks,
    const MdvDiagram(
      id: 'fixture-d1',
      span: MdvSpan(startLine: 9, endLine: 11, startOffset: 63, endOffset: 95),
      source: 'graph TD; A-->B',
      engine: 'mermaid',
    ),
  ],
  footnotes: const [],
);

/// [fakeLongTree] plus one footnote definition, so the adapter appends
/// its trailing footnotes item (`itemCount == blocks + 1`;
/// `startLineForIndex` returns null for it — the scrollspy "line holds,
/// progress keeps going" case).
MdvTree fakeLongTreeWithFootnotes({int paragraphs = 8}) => MdvTree(
  version: 1,
  blocks: fakeLongTree(paragraphs: paragraphs).blocks,
  footnotes: const [
    MdvFootnoteDef(
      id: 'long-fn1',
      span: MdvSpan(startLine: 99, endLine: 99, startOffset: 0, endOffset: 0),
      index: 1,
      refCount: 1,
      blocks: [
        MdvParagraph(
          id: 'long-fn1-p',
          children: [MdvText(value: 'footnote body')],
        ),
      ],
    ),
  ],
);

/// The v2 native-path extension of `reader_test.dart`'s in-file
/// `_FakeDocRenderer` (which may NOT change, and deliberately does NOT
/// override [DocRenderer.renderTree] — the inherited real one throws on
/// a host with no FFI library, exercising the Reader's
/// renderTree-failure → webview fallback under every pre-existing
/// webview test, byte-untouched). THIS fake overrides [renderTree] with
/// a canned typed tree (and counts calls), so tests can put the Reader
/// on the native engine — and prove renderTree runs at most once per
/// document across Aa steps, theme flips, and engine switches.
class FakeTreeDocRenderer extends DocRenderer {
  FakeTreeDocRenderer({MdvTree Function() tree = fakeTree, this._parseChildren})
    : _treeBuilder = tree;

  final MdvTree Function() _treeBuilder;

  /// Overrides the parse fixture's `children` array (e.g. to give the
  /// outline a deep heading whose line matches a [fakeLongTree] block).
  /// Null keeps `_FakeDocRenderer`'s H1-"Hello" + paragraph shape.
  final List<Map<String, dynamic>>? _parseChildren;

  int parseCalls = 0;
  int renderCalls = 0;
  int renderTreeCalls = 0;

  /// Non-null makes [renderTree] throw it — the fallback-posture tests'
  /// hook (a real `renderTreeDoc` failure can be anything, so the
  /// Reader must catch broadly).
  Object? throwOnRenderTree;

  /// The resolver the most recent [render] call received (mirrors
  /// `_FakeDocRenderer.lastResolver`).
  MdvResolver? lastResolver;

  @override
  Map<String, dynamic> parse(String markdown) {
    parseCalls++;
    return {
      'version': 1,
      'kind': 'document',
      'children':
          _parseChildren ??
          [
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
  MdvTree renderTree(Object doc) {
    renderTreeCalls++;
    final error = throwOnRenderTree;
    if (error != null) throw error;
    return _treeBuilder();
  }

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
