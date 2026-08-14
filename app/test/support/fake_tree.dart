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
