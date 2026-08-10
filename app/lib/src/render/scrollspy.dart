import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The `WebViewController.addJavaScriptChannel` name the injected script
/// (below) posts scroll updates to, and `reader.dart` listens on.
const String scrollSpyChannelName = 'ScrollSpy';

/// Appends the scrollspy `<script>` to [html] at `lastIndexOf('</body>')` —
/// **never** `indexOf`/`.replace()`. A rendered page that embeds mermaid
/// (`assets.MermaidJS()`, inlined verbatim into a `<script>` tag) can
/// contain the literal substring `</body>` more than once: mermaid's own
/// bundled sanitizer builds an HTML-serialization string like
/// `'<html>...<body>'+x+"</body></html>"` internally, which lands *before*
/// the document's real closing tag. A first-match replace would splice this
/// script into the middle of that inline JS string, prematurely closing it
/// and dumping the rest of mermaid's source as visible page text (the same
/// failure mode MDViewer.Desktop's `viewer.ts` documents and works around
/// identically). Targeting the *last* occurrence is always the actual
/// closing `</body>` of the outer document.
String injectScrollSpy(String html) {
  final idx = html.lastIndexOf('</body>');
  if (idx == -1) return html + _scrollSpyScript;
  return html.substring(0, idx) + _scrollSpyScript + html.substring(idx);
}

/// A `runJavaScript` call scrolling the loaded page to the heading at
/// [line] (`[data-md-line="<line>"]`) — the outline/search "jump to
/// heading" affordance (wired up by later tasks; the injected script
/// exposes the `window.__mdvScrollToLine` function this calls).
String scrollToLineScript(int line) =>
    'window.__mdvScrollToLine && window.__mdvScrollToLine($line);';

/// A `runJavaScript` call restoring a persisted scroll position — [progress]
/// is the same 0..1 fraction `ScrollSpyPayload.progress` reports, clamped
/// defensively since a persisted value could in principle be corrupt.
String scrollToProgressScript(double progress) {
  final clamped = progress.clamp(0.0, 1.0);
  return 'window.__mdvScrollToProgress && window.__mdvScrollToProgress($clamped);';
}

/// One `ScrollSpy` channel message: overall scroll [progress] (0..1) and
/// the topmost heading's source [line] currently at/above the viewport's
/// reading offset — 0 when no heading has scrolled past yet.
@immutable
class ScrollSpyPayload {
  const ScrollSpyPayload({required this.progress, required this.line});

  final double progress;
  final int line;

  /// Parses a `ScrollSpy.postMessage` JSON string. Returns null for
  /// anything that isn't a well-formed `{"p": <number>, "h": <number>}`
  /// object — malformed JSON, a non-object top level, or a `p` that isn't
  /// numeric/numeric-string — rather than throwing. This is a trust
  /// boundary: the message body is produced by script running inside the
  /// loaded (rendered-Markdown, effectively untrusted-content) page, so
  /// coercion must degrade to "ignore this message", never crash the host.
  /// `h` alone being unparseable still yields a payload (line defaults to
  /// 0) since `p` is the field the progress hairline actually depends on.
  static ScrollSpyPayload? tryParse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final progress = _toDouble(decoded['p']);
    if (progress == null) return null;
    final line = _toInt(decoded['h']) ?? 0;

    return ScrollSpyPayload(progress: progress.clamp(0.0, 1.0), line: line);
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.isFinite ? value.toDouble() : null;
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }

  static int? _toInt(Object? value) {
    if (value is num) return value.isFinite ? value.round() : null;
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed.round() : null;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ScrollSpyPayload &&
      other.progress == progress &&
      other.line == line;

  @override
  int get hashCode => Object.hash(progress, line);

  @override
  String toString() => 'ScrollSpyPayload(progress: $progress, line: $line)';
}

/// Injected once per render: on scroll (rAF-throttled), posts
/// `{"p": <0..1>, "h": <line>}` to the [scrollSpyChannelName] channel;
/// exposes `window.__mdvScrollToLine`/`window.__mdvScrollToProgress` for the
/// host side to drive. `[data-md-line]` is `sourceMap: true`'s top-level
/// block annotation (`ffi/README.md`'s `SourceMap` option) — verified
/// empirically present on rendered `<h1>`/`<p>`/etc. elements.
///
/// The `top <= 80` reading-offset heuristic mirrors MDViewer.Desktop's
/// `viewer.ts` scrollspy script (its own header height approximation) —
/// carried over as a starting point, not re-derived from this app's actual
/// (blurred, 1px-bordered) Reader header height; Task 8's device E2E is
/// where a mismatch would actually be visible.
const String _scrollSpyScript =
    '''
<script>
(function(){
  function report(){
    var marked = document.querySelectorAll('[data-md-line]');
    var active = marked.length ? marked[0] : null;
    for (var i = 0; i < marked.length; i++){
      var el = marked[i];
      if (el.getBoundingClientRect().top <= 80) { active = el; } else { break; }
    }
    var docEl = document.documentElement;
    var scrollable = Math.max(docEl.scrollHeight - window.innerHeight, 1);
    var p = Math.min(1, Math.max(0, window.scrollY / scrollable));
    var h = 0;
    if (active) {
      var parsed = parseInt(active.getAttribute('data-md-line'), 10);
      h = isNaN(parsed) ? 0 : parsed;
    }
    if (window.$scrollSpyChannelName && window.$scrollSpyChannelName.postMessage) {
      window.$scrollSpyChannelName.postMessage(JSON.stringify({p: p, h: h}));
    }
  }
  var scheduled = false;
  function onScroll(){
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(function(){ scheduled = false; report(); });
  }
  window.addEventListener('scroll', onScroll, {passive: true});
  window.__mdvScrollToLine = function(line){
    var el = document.querySelector('[data-md-line="' + line + '"]');
    if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});
  };
  window.__mdvScrollToProgress = function(p){
    var docEl = document.documentElement;
    var scrollable = Math.max(docEl.scrollHeight - window.innerHeight, 1);
    var clamped = Math.min(1, Math.max(0, p));
    window.scrollTo(0, clamped * scrollable);
  };
  report();
})();
</script>''';
