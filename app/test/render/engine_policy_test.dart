import 'package:app/src/render/engine_policy.dart';
import 'package:app/src/vault/vault_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';

/// Fixture helpers — hand-built typed trees. Ids are arbitrary (identity
/// is irrelevant to the walk); spans omitted (null) throughout.
MdvTree _tree(List<MdvBlock> blocks, {List<MdvBlock> footnotes = const []}) =>
    MdvTree(version: 1, blocks: blocks, footnotes: footnotes);

MdvDiagram _mermaid({String id = 'd1'}) =>
    MdvDiagram(id: id, source: 'graph TD; A-->B', engine: 'mermaid');

MdvParagraph _para(String text) => MdvParagraph(
  id: 'p-$text',
  children: [MdvText(value: text)],
);

void main() {
  group('treeContainsMermaid', () {
    test('top-level mermaid diagram is detected', () {
      final tree = _tree([_para('hi'), _mermaid()]);
      expect(treeContainsMermaid(tree), isTrue);
    });

    test('mermaid nested in a blockQuote is detected', () {
      final tree = _tree([
        MdvBlockQuote(id: 'q', blocks: [_para('quoted'), _mermaid()]),
      ]);
      expect(treeContainsMermaid(tree), isTrue);
    });

    test('mermaid nested in an admonition is detected', () {
      final tree = _tree([
        MdvAdmonition(
          id: 'a',
          variant: 'note',
          title: 'Note',
          blocks: [_mermaid()],
        ),
      ]);
      expect(treeContainsMermaid(tree), isTrue);
    });

    test('mermaid nested in a list item is detected', () {
      final tree = _tree([
        MdvList(
          id: 'l',
          ordered: false,
          start: 1,
          tight: true,
          items: [
            MdvListItem(id: 'i1', task: null, blocks: [_para('one')]),
            MdvListItem(id: 'i2', task: null, blocks: [_mermaid()]),
          ],
        ),
      ]);
      expect(treeContainsMermaid(tree), isTrue);
    });

    test('mermaid nested in a definition-list description is detected', () {
      final tree = _tree([
        MdvDefinitionList(
          id: 'dl',
          blocks: [
            MdvDefinitionTerm(
              id: 'dt',
              children: [MdvText(value: 'term')],
            ),
            MdvDefinitionDesc(id: 'dd', blocks: [_mermaid()]),
          ],
        ),
      ]);
      expect(treeContainsMermaid(tree), isTrue);
    });

    test('mermaid inside a footnote definition (tree.footnotes) is '
        'detected', () {
      final tree = _tree(
        [_para('body')],
        footnotes: [
          MdvFootnoteDef(id: 'fn', index: 1, refCount: 1, blocks: [_mermaid()]),
        ],
      );
      expect(treeContainsMermaid(tree), isTrue);
    });

    test('mermaid inside an inline-body footnote def in blocks is '
        'detected', () {
      // FootnoteDef appearing in the main blocks array (defensive: the
      // walk treats it as a container wherever it shows up).
      final tree = _tree([
        MdvFootnoteDef(id: 'fn', index: 1, refCount: 1, blocks: [_mermaid()]),
      ]);
      expect(treeContainsMermaid(tree), isTrue);
    });

    test('diagram with a non-mermaid engine is NOT a hit', () {
      final tree = _tree([
        MdvDiagram(id: 'd', source: 'digraph {}', engine: 'graphviz'),
      ]);
      expect(treeContainsMermaid(tree), isFalse);
    });

    test('plain document has no hit', () {
      final tree = _tree([
        MdvHeading(
          id: 'h',
          level: 1,
          children: [MdvText(value: 'Title')],
        ),
        _para('text'),
        MdvCodeBlock(
          id: 'c',
          language: 'mermaid', // a code FENCE named mermaid is not a diagram
          label: 'mermaid',
          runs: null,
          text: 'graph TD; A-->B',
        ),
        MdvThematicBreak(id: 't'),
      ]);
      expect(treeContainsMermaid(tree), isFalse);
    });

    test('MdvUnknownBlock present: no hit, no throw', () {
      final tree = _tree([
        MdvUnknownBlock(
          id: 'u',
          kind: 'futureKind',
          raw: {'kind': 'futureKind', 'engine': 'mermaid'},
        ),
        _para('after'),
      ]);
      expect(() => treeContainsMermaid(tree), returnsNormally);
      expect(treeContainsMermaid(tree), isFalse);
    });

    test('MdvTree.fromMap-decoded fixture with nesting is detected', () {
      // Canned version-1 wire map: a blockQuote holding a list whose
      // second item carries the mermaid diagram — guards the hand-built
      // fixtures against drifting from the real decode shape.
      final wire = <String, dynamic>{
        'version': 1,
        'blocks': [
          {
            'kind': 'paragraph',
            'id': 'p1',
            'children': [
              {'kind': 'text', 'value': 'intro'},
            ],
          },
          {
            'kind': 'blockQuote',
            'id': 'q1',
            'blocks': [
              {
                'kind': 'list',
                'id': 'l1',
                'ordered': false,
                'start': 1,
                'tight': true,
                'items': [
                  {
                    'kind': 'listItem',
                    'id': 'i1',
                    'task': null,
                    'blocks': [
                      {
                        'kind': 'paragraph',
                        'id': 'p2',
                        'children': [
                          {'kind': 'text', 'value': 'plain item'},
                        ],
                      },
                    ],
                  },
                  {
                    'kind': 'listItem',
                    'id': 'i2',
                    'task': null,
                    'blocks': [
                      {
                        'kind': 'diagram',
                        'id': 'd1',
                        'source': 'graph TD; A-->B',
                        'engine': 'mermaid',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
        'footnotes': <dynamic>[],
      };
      final tree = MdvTree.fromMap(wire);
      expect(treeContainsMermaid(tree), isTrue);

      // Same wire shape with the diagram's engine swapped: no hit —
      // detection is engine-keyed, not type-keyed.
      final blocks = wire['blocks'] as List<dynamic>;
      final quote = blocks[1] as Map<String, dynamic>;
      final list =
          (quote['blocks'] as List<dynamic>)[0] as Map<String, dynamic>;
      final item2 = (list['items'] as List<dynamic>)[1] as Map<String, dynamic>;
      final diagram =
          (item2['blocks'] as List<dynamic>)[0] as Map<String, dynamic>;
      diagram['engine'] = 'plantuml';
      expect(treeContainsMermaid(MdvTree.fromMap(wire)), isFalse);
    });
  });

  group('resolveEngine precedence', () {
    test('override=native + mermaid doc → native (escape hatch wins)', () {
      expect(
        resolveEngine(persistedOverride: ReaderEngine.native, hasMermaid: true),
        ReaderEngine.native,
      );
    });

    test('override=webview + plain doc → webview', () {
      expect(
        resolveEngine(
          persistedOverride: ReaderEngine.webview,
          hasMermaid: false,
        ),
        ReaderEngine.webview,
      );
    });

    test('no override + mermaid doc → webview', () {
      expect(
        resolveEngine(persistedOverride: null, hasMermaid: true),
        ReaderEngine.webview,
      );
    });

    test('no override + plain doc → native', () {
      expect(
        resolveEngine(persistedOverride: null, hasMermaid: false),
        ReaderEngine.native,
      );
    });
  });

  group('ReaderEngine wire encoding', () {
    test('encode/decode round-trips both engines', () {
      for (final engine in ReaderEngine.values) {
        expect(ReaderEngine.decode(engine.wire), engine);
      }
      expect(ReaderEngine.native.wire, 'native');
      expect(ReaderEngine.webview.wire, 'webview');
    });

    test('corrupt or missing value sanitizes to null, never throws', () {
      expect(ReaderEngine.decode(null), isNull);
      expect(ReaderEngine.decode(''), isNull);
      expect(ReaderEngine.decode('NATIVE'), isNull);
      expect(ReaderEngine.decode('web view'), isNull);
      expect(ReaderEngine.decode('garbage'), isNull);
    });
  });

  group('prefs keys', () {
    test('engineKey mirrors the reader.scroll key shape', () {
      expect(
        engineKey(VaultSource.sample, 'guides/Welcome.md'),
        'reader.engine.sample:guides/Welcome.md',
      );
      expect(
        engineKey(VaultSource.folder, 'a b/c.md'),
        'reader.engine.folder:a b/c.md',
      );
      expect(
        engineKey(VaultSource.openedFile, 'Shared.md'),
        'reader.engine.openedFile:Shared.md',
      );
    });

    test('lineKey mirrors the reader.scroll key shape', () {
      expect(
        lineKey(VaultSource.sample, 'guides/Welcome.md'),
        'reader.line.sample:guides/Welcome.md',
      );
      expect(
        lineKey(VaultSource.folder, 'notes/x.md'),
        'reader.line.folder:notes/x.md',
      );
    });
  });
}
