import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mdviewer/mdviewer.dart';

import '../tokens.dart';

/// One heading in a parsed document's outline — design/README.md §03
/// ("On this page"), keyed by [line] (the heading's 1-based source line,
/// from the AST's `span.startLine`) so the scrollspy channel's `h` payload
/// and `window.__mdvScrollToLine` (scrollspy.dart) can address it directly.
@immutable
class OutlineHeading {
  const OutlineHeading({
    required this.level,
    required this.text,
    required this.line,
  });

  final int level;
  final String text;
  final int line;

  @override
  bool operator ==(Object other) =>
      other is OutlineHeading &&
      other.level == level &&
      other.text == text &&
      other.line == line;

  @override
  int get hashCode => Object.hash(level, text, line);

  @override
  String toString() => 'OutlineHeading(level: $level, "$text", line: $line)';
}

/// The analyzed shape of a parsed document — outline, word count, and
/// estimated read time — mirroring MDViewer.Desktop's `docmodel.rs` exactly
/// (same walk rules, same `words/220` read-time formula) so the two apps
/// report identical numbers for the same document.
@immutable
class DocModel {
  const DocModel({
    required this.outline,
    required this.words,
    required this.readMinutes,
  });

  /// The empty document: no headings, no words, a 1-minute floor read time.
  static const DocModel empty = DocModel(outline: [], words: 0, readMinutes: 1);

  final List<OutlineHeading> outline;
  final int words;
  final int readMinutes;

  /// Walks [parsed] — the `Map<String, dynamic>` `Mdviewer.parse` decodes
  /// the v1 AST JSON to (top-level `version`/`kind`/`children` fields; see
  /// `vendor/markdownviewer/document/json.go`) — and computes the model.
  ///
  /// ## Real codec shape (verified against the real linked library — a
  /// v0.7.0-era capture; the version-1 codec is pinned/append-only — not
  /// inferred from the FFI README's prose)
  ///
  /// Container nodes use `"children"`, and a leaf's textual payload lives
  /// in `"value"` — NOT the plan's placeholder `"kids"`/`"text"` field
  /// names. Verified by parsing `"# Title\n\nsome words here\n\n## Sub
  /// Head\n\nmore\n"` through the real `libmdviewer` dylib (built via
  /// `vendor/markdownviewer/scripts/build-ffi.sh` for this verification;
  /// see the task-5 report):
  ///
  /// ```json
  /// {"version":1,"kind":"document","children":[
  ///   {"kind":"heading","level":1,"anchorId":"title",
  ///    "span":{"startLine":1,"endLine":1,"startOffset":0,"endOffset":7},
  ///    "children":[{"kind":"text","value":"Title"}]},
  ///   {"kind":"paragraph","span":{"startLine":3,...},
  ///    "children":[{"kind":"text","value":"some words here"}]},
  ///   ...
  /// ]}
  /// ```
  ///
  /// ## Rules (identical to `docmodel.rs`'s documented behavior)
  ///
  /// - **Outline**: every `heading` node in document order becomes
  ///   `(level, text, span.startLine)`. `text` is the node's flattened
  ///   textual content (below). A heading missing a `span` reports line 0
  ///   (defensive; real parses with `sourceMap: true` always populate it).
  /// - **Flattened heading text**: concatenation, in document order, of
  ///   every descendant `text` node's `value` AND every descendant
  ///   `codeSpan` node's `value` — inline code counts as text for display
  ///   (`# A *b* \`c\`` flattens to `"A b c"`; `emphasis`/`strong`/etc.
  ///   wrapper nodes carry no text themselves, only their children do).
  /// - **Word count**: whitespace-split token count over the `value` of
  ///   every `text` node in the whole document (headings included).
  ///   Narrower than the heading-text rule: `codeSpan` is excluded from
  ///   the word count so short inline-code tokens don't inflate the
  ///   reading-time estimate. Verified: `"# Title\n\nsome words here\n\n##
  ///   Sub Head\n\nmore\n"` yields 7 words (Title, some, words, here, Sub,
  ///   Head, more).
  /// - **readMinutes**: `max(1, round(words / 220))`.
  static DocModel analyze(Map<String, dynamic> parsed) {
    final outline = <OutlineHeading>[];
    final words = _WordCounter();

    final children = parsed['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map) {
          _walk(_asStringMap(child), outline, words);
        }
      }
    }

    final readMinutes = math.max(1, (words.total / 220).round());
    return DocModel(
      outline: outline,
      words: words.total,
      readMinutes: readMinutes,
    );
  }

  static void _walk(
    Map<String, dynamic> node,
    List<OutlineHeading> outline,
    _WordCounter words,
  ) {
    final kind = node['kind'] as String? ?? '';

    if (kind == 'heading') {
      final level = _asInt(node['level']) ?? 0;
      final span = node['span'];
      final line = span is Map ? _asInt(span['startLine']) ?? 0 : 0;
      outline.add(
        OutlineHeading(level: level, text: _flattenText(node), line: line),
      );
    }

    if (kind == 'text') {
      final value = node['value'];
      if (value is String) words.add(value);
    }

    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map) _walk(_asStringMap(child), outline, words);
      }
    }
  }

  static String _flattenText(Map<String, dynamic> node) {
    final out = StringBuffer();
    _flattenInto(node, out);
    return out.toString();
  }

  static void _flattenInto(Map<String, dynamic> node, StringBuffer out) {
    final kind = node['kind'] as String? ?? '';
    if (kind == 'text' || kind == 'codeSpan') {
      final value = node['value'];
      if (value is String) out.write(value);
      return;
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map) _flattenInto(_asStringMap(child), out);
      }
    }
  }

  static Map<String, dynamic> _asStringMap(Map raw) =>
      raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw);

  static int? _asInt(Object? v) => v is num ? v.toInt() : null;
}

class _WordCounter {
  int total = 0;

  /// Whitespace-split token count, matching Rust's `str::split_whitespace`
  /// (splits on any run of whitespace, skips leading/trailing/empty runs).
  void add(String value) {
    for (final token in value.split(RegExp(r'\s+'))) {
      if (token.isNotEmpty) total++;
    }
  }
}

/// Wraps [Mdviewer] for the Reader: parse-once, render-many over a mobile
/// prose stylesheet. Instance methods (not static) so tests can subclass
/// and override [parse]/[render] with a fake — `Mdviewer.instance` only
/// resolves its native library on a real iOS/Android process (or a host
/// with `dist/ffi`/`MDVIEWER_LIBRARY_PATH` set, which this app's `flutter
/// test` run does not set — see `mdviewer_version.dart`'s doc comment), so
/// widget tests that need a loaded Reader inject a fake renderer instead of
/// exercising the real FFI call.
///
/// [_mdv] resolves `Mdviewer.instance` lazily (on first actual use inside
/// [parse]/[render]) rather than eagerly in the constructor: a test
/// subclass that overrides both and never touches `_mdv` must be
/// constructible on a host with no `libmdviewer` reachable at all — eagerly
/// resolving it in an initializer list would throw before the subclass's
/// constructor body (or its overrides) ever run.
class DocRenderer {
  DocRenderer({Mdviewer? mdv}) : _explicitMdv = mdv;

  final Mdviewer? _explicitMdv;
  Mdviewer get _mdv => _explicitMdv ?? Mdviewer.instance;

  /// Parses [markdown] once, with `sourceMap: true` so the rendered HTML
  /// carries `data-md-line` attributes for scrollspy.dart to read.
  Map<String, dynamic> parse(String markdown) =>
      _mdv.parse(markdown, options: const MdvOptions(sourceMap: true));

  /// Re-renders [doc] (a previously [parse]d document — `Map` or JSON
  /// `String`) themed for [brightness] at [textScale], resolving images via
  /// [resolver] (resolver.dart's `DocImages.toResolver()`).
  ///
  /// ## Text-scale mechanism: `extraCss` (library ≥ v0.8)
  ///
  /// `MdvOptions.extraCss` appends the given CSS AFTER the library's own
  /// base + theme styling in the assembled page — the append-only hook
  /// v0.8 added precisely for this app's ledgered gap. So every
  /// structural `base.css` rule (tables, code blocks, blockquotes,
  /// admonitions, footnotes, mermaid/KaTeX layout) survives untouched,
  /// and [mobileProseOverrideCss]'s selector-identical overrides
  /// (`.markdown-body h1`, `.markdown-body h2`, ...) win by CSS-cascade
  /// source order alone — no `!important` needed.
  ///
  /// (Historical note: on v0.7 this took a workaround — `stylesheet:`
  /// REPLACES `theme.BaseCSS()` wholesale per `render/html/page.go`, so
  /// `render()` had to fetch `base.css`'s bytes via
  /// `Mdviewer.asset('base.css')` and pass `stylesheet: base.css +
  /// overrides` to reproduce the base styling verbatim. `extraCss`
  /// retires that concatenation; `themeOverrides` remains unsuitable —
  /// it only emits `:root{--md-*}` custom-property overrides, and
  /// `base.css` has zero font-size variable hooks.)
  ///
  /// Also opts in to `codeHeader`: code blocks render inside an
  /// `md-code` container with a language-label + Copy-button header
  /// (design §Reader), and full-page output carries the library's inline
  /// clipboard JS. That JS guards on `navigator.clipboard`, which some
  /// WebView origins don't expose — the button is then inert, not a
  /// crash.
  String render(
    Object doc, {
    required Brightness brightness,
    required double textScale,
    MdvResolver? resolver,
  }) {
    return _mdv.renderDoc(
      doc,
      options: MdvOptions(
        theme: brightness == Brightness.dark ? 'dark' : 'light',
        sourceMap: true,
        extraCss: mobileProseOverrideCss(textScale),
        codeHeader: true,
        resolver: resolver,
      ),
    );
  }
}

/// The mobile prose override block `DocRenderer.render` passes as
/// `MdvOptions.extraCss` (appended after the library's base + theme
/// styling) — design/README.md §Fidelity's mobile type scale
/// (body 15/1.68, H1 27/700, H2 19/600, code 12) times [scale] (the
/// `AppState.textScale` step), keyed to the exact same `.markdown-body …`
/// selectors `theme/base.css` uses so the cascade lets these win by source
/// order. A pure string builder (no FFI) so it's unit-testable without a
/// loaded `libmdviewer`.
///
/// Margins/padding are left at their literal design values (not scaled by
/// [scale]) — only H1/H2's `letter-spacing` scale proportionally, since
/// `AppTypeScale` defines those as a ratio of their own font size
/// (`-0.02 * h1Size`, etc.) rather than an independent literal.
String mobileProseOverrideCss(double scale) {
  final body = AppTypeScale.bodySize * scale;
  final h1 = AppTypeScale.h1Size * scale;
  final h1Ls = AppTypeScale.h1LetterSpacing * scale;
  final h2 = AppTypeScale.h2Size * scale;
  final h2Ls = AppTypeScale.h2LetterSpacing * scale;
  final h3 = AppTypeScale.h3Size * scale;
  final code = AppTypeScale.codeSize * scale;

  return 'body.markdown-body{'
      'font-size:${_px(body)};'
      'line-height:${AppTypeScale.bodyLineHeight};'
      'padding:22px 20px;'
      '}\n'
      '.markdown-body h1{'
      'font-size:${_px(h1)};'
      'font-weight:${_cssWeight(AppTypeScale.h1Weight)};'
      'letter-spacing:${_px(h1Ls)};'
      'line-height:${AppTypeScale.h1LineHeight};'
      '}\n'
      '.markdown-body h2{'
      'font-size:${_px(h2)};'
      'font-weight:${_cssWeight(AppTypeScale.h2Weight)};'
      'letter-spacing:${_px(h2Ls)};'
      'border-bottom-width:${_px(AppTypeScale.h2BorderBottomWidth)};'
      'padding-bottom:${_px(AppTypeScale.h2PaddingBottom)};'
      'margin-top:${_px(AppTypeScale.h2MarginTop)};'
      'margin-bottom:${_px(AppTypeScale.h2MarginBottom)};'
      '}\n'
      '.markdown-body h3{'
      'font-size:${_px(h3)};'
      'font-weight:${_cssWeight(AppTypeScale.h3Weight)};'
      'margin-top:${_px(AppTypeScale.h3MarginTop)};'
      'margin-bottom:${_px(AppTypeScale.h3MarginBottom)};'
      '}\n'
      '.markdown-body code,.markdown-body pre,.markdown-body kbd{'
      'font-size:${_px(code)};'
      'line-height:${AppTypeScale.codeLineHeight};'
      '}\n';
}

String _px(double value) => '${value.toStringAsFixed(2)}px';

/// `FontWeight.value` (e.g. `FontWeight.w700.value == 700`) IS the CSS
/// numeric weight already — no lookup table needed.
String _cssWeight(FontWeight weight) => weight.value.toString();
