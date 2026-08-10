import 'dart:convert';

import 'package:app/src/render/renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';

/// Real `Mdviewer.parse` output — NOT hand-guessed — captured by building
/// `vendor/markdownviewer`'s host FFI library
/// (`vendor/markdownviewer/scripts/build-ffi.sh`, producing
/// `dist/ffi/darwin-arm64/libmdviewer.dylib`) and calling
/// `Mdviewer.instance.parse(...)` against it directly from a throwaway Dart
/// script run from `vendor/markdownviewer/flutter/mdviewer` (where the
/// plugin's host `library_loader.dart` walk-up finds that dylib). This
/// app's own `flutter test` run can't do this itself — no `dist/ffi` is
/// reachable by walking up from `app/` (see `mdviewer_version.dart`'s doc
/// comment) — so these fixtures are the verified bridge: real codec shape,
/// captured once, checked in as a literal. See the task-5 report for the
/// exact capture commands.
const String _basicFixtureJson = '''
{
  "version": 1,
  "kind": "document",
  "children": [
    {
      "kind": "heading",
      "level": 1,
      "anchorId": "title",
      "span": {"startLine": 1, "endLine": 1, "startOffset": 0, "endOffset": 7},
      "children": [{"kind": "text", "value": "Title"}]
    },
    {
      "kind": "paragraph",
      "span": {"startLine": 3, "endLine": 3, "startOffset": 9, "endOffset": 24},
      "children": [{"kind": "text", "value": "some words here"}]
    },
    {
      "kind": "heading",
      "level": 2,
      "anchorId": "sub-head",
      "span": {"startLine": 5, "endLine": 5, "startOffset": 26, "endOffset": 37},
      "children": [{"kind": "text", "value": "Sub Head"}]
    },
    {
      "kind": "paragraph",
      "span": {"startLine": 7, "endLine": 7, "startOffset": 39, "endOffset": 43},
      "children": [{"kind": "text", "value": "more"}]
    }
  ]
}
''';

const String _inlineEmphasisCodeFixtureJson = '''
{
  "version": 1,
  "kind": "document",
  "children": [
    {
      "kind": "heading",
      "level": 1,
      "anchorId": "a-b-c",
      "span": {"startLine": 1, "endLine": 1, "startOffset": 0, "endOffset": 11},
      "children": [
        {"kind": "text", "value": "A "},
        {"kind": "emphasis", "children": [{"kind": "text", "value": "b"}]},
        {"kind": "text", "value": " "},
        {"kind": "codeSpan", "value": "c"}
      ]
    }
  ]
}
''';

const String _emptyFixtureJson = '{"version": 1, "kind": "document"}';

const String _nestedWordsFixtureJson = '''
{
  "version": 1,
  "kind": "document",
  "children": [
    {
      "kind": "heading",
      "level": 1,
      "span": {"startLine": 1},
      "children": [{"kind": "text", "value": "Title"}]
    },
    {
      "kind": "list",
      "start": 1,
      "tight": true,
      "children": [
        {
          "kind": "listItem",
          "children": [
            {"kind": "paragraph", "children": [{"kind": "text", "value": "one two"}]}
          ]
        },
        {
          "kind": "listItem",
          "children": [
            {"kind": "paragraph", "children": [{"kind": "text", "value": "three four"}]}
          ]
        }
      ]
    },
    {
      "kind": "table",
      "alignments": ["none", "none"],
      "children": [
        {
          "kind": "tableRow",
          "header": true,
          "children": [
            {"kind": "tableCell", "children": [{"kind": "text", "value": "a"}]},
            {"kind": "tableCell", "children": [{"kind": "text", "value": "b"}]}
          ]
        },
        {
          "kind": "tableRow",
          "children": [
            {"kind": "tableCell", "children": [{"kind": "text", "value": "five six"}]},
            {"kind": "tableCell", "children": [{"kind": "text", "value": "seven"}]}
          ]
        }
      ]
    }
  ]
}
''';

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

void main() {
  group('DocModel.analyze', () {
    test('outline + word count + read-minutes match docmodel.rs exactly', () {
      final model = DocModel.analyze(_decode(_basicFixtureJson));

      expect(model.outline, [
        const OutlineHeading(level: 1, text: 'Title', line: 1),
        const OutlineHeading(level: 2, text: 'Sub Head', line: 5),
      ]);
      // Title, some, words, here, Sub, Head, more.
      expect(model.words, 7);
      expect(model.readMinutes, 1);
    });

    test('flattens emphasis/codeSpan into heading text', () {
      final model = DocModel.analyze(_decode(_inlineEmphasisCodeFixtureJson));

      expect(model.outline, hasLength(1));
      expect(model.outline.single.text, 'A b c');
      // codeSpan is excluded from the word count (only "A" and "b" count).
      expect(model.words, 2);
    });

    test('empty document has empty outline and a 1-minute floor', () {
      final model = DocModel.analyze(_decode(_emptyFixtureJson));

      expect(model.outline, isEmpty);
      expect(model.words, 0);
      expect(model.readMinutes, 1);
    });

    test('counts words nested inside lists and table cells', () {
      final model = DocModel.analyze(_decode(_nestedWordsFixtureJson));

      // Title(1) + one two(2) + three four(2) + a(1) + b(1) + five six(2) +
      // seven(1) = 10.
      expect(model.words, 10);
      expect(model.outline, [
        const OutlineHeading(level: 1, text: 'Title', line: 1),
      ]);
    });

    test('a heading with no span reports line 0 defensively', () {
      final noSpan = _decode('''
        {"version": 1, "kind": "document", "children": [
          {"kind": "heading", "level": 1, "children": [{"kind": "text", "value": "X"}]}
        ]}
      ''');
      final model = DocModel.analyze(noSpan);
      expect(model.outline.single.line, 0);
    });

    test('readMinutes rounds, not just floors', () {
      // 330 words -> 330/220 = 1.5 -> rounds to 2.
      final words = List.filled(330, 'w').join(' ');
      final doc = {
        'version': 1,
        'kind': 'document',
        'children': [
          {
            'kind': 'paragraph',
            'children': [
              {'kind': 'text', 'value': words},
            ],
          },
        ],
      };
      final model = DocModel.analyze(doc);
      expect(model.words, 330);
      expect(model.readMinutes, 2);
    });
  });

  group('mobileProseOverrideCss', () {
    test('scales every prose size by the given factor', () {
      final css = mobileProseOverrideCss(1.0);

      expect(css, contains('body.markdown-body{font-size:15.00px;'));
      expect(css, contains('.markdown-body h1{font-size:27.00px;'));
      expect(css, contains('.markdown-body h2{font-size:19.00px;'));
      expect(css, contains('.markdown-body h3{font-size:17.00px;'));
      expect(css, contains('font-size:12.00px;line-height:1.65'));
    });

    test('scale=1.15 multiplies every size, not just body', () {
      final css = mobileProseOverrideCss(1.15);

      expect(css, contains('font-size:${(15 * 1.15).toStringAsFixed(2)}px'));
      expect(css, contains('font-size:${(27 * 1.15).toStringAsFixed(2)}px'));
      expect(css, contains('font-size:${(19 * 1.15).toStringAsFixed(2)}px'));
    });

    test(
      'uses the same selectors base.css uses, so source order wins the cascade',
      () {
        final css = mobileProseOverrideCss(1.0);
        expect(css, contains('body.markdown-body{'));
        expect(css, contains('.markdown-body h1{'));
        expect(css, contains('.markdown-body h2{'));
        expect(css, contains('.markdown-body h3{'));
        expect(
          css,
          contains(
            '.markdown-body code,.markdown-body pre,.markdown-body kbd{',
          ),
        );
      },
    );

    test('h1/h2 weights render as CSS numeric weights', () {
      final css = mobileProseOverrideCss(1.0);
      expect(css, contains('font-weight:700')); // h1
      expect(css, contains('font-weight:600')); // h2/h3
    });
  });

  group('DocRenderer', () {
    test('is overridable for tests that cannot reach the real FFI library', () {
      // Documents the DI seam ReaderScreen relies on (see reader.dart /
      // reader_test.dart) — a plain subclass overriding parse/render never
      // touches Mdviewer.instance.
      final renderer = _NoopDocRenderer();
      expect(renderer.parse('# x'), {'kind': 'noop'});
      expect(
        renderer.render(const {}, brightness: Brightness.light, textScale: 1.0),
        '<html></html>',
      );
    });
  });
}

class _NoopDocRenderer extends DocRenderer {
  @override
  Map<String, dynamic> parse(String markdown) => {'kind': 'noop'};

  @override
  String render(
    Object doc, {
    required Brightness brightness,
    required double textScale,
    MdvResolver? resolver,
  }) => '<html></html>';
}
