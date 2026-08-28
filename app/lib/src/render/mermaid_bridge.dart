import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'renderer.dart';

/// The outcome of one [MermaidBridge.render] call: either a rendered SVG
/// string, or a (non-fatal, always-handled) failure reason.
@immutable
class MermaidRenderResult {
  const MermaidRenderResult._({required this.ok, this.svg, this.error});

  factory MermaidRenderResult.success(String svg) =>
      MermaidRenderResult._(ok: true, svg: svg);

  factory MermaidRenderResult.failure(String error) =>
      MermaidRenderResult._(ok: false, error: error);

  final bool ok;
  final String? svg;
  final String? error;
}

/// Renders Mermaid diagram source to SVG using the library's
/// `mermaid-bridge.js` primitive (`mdvRenderMermaid(id, source, theme)`)
/// inside a hidden, offscreen webview — per the design note
/// `.superpowers/specs/2026-08-28 Mermaid Offscreen-SVG Direction.md`
/// in the vendored `markdownviewer` checkout: SVG generation stays a
/// host-side (webview) responsibility, not a Go-side rendering pipeline.
///
/// ONE instance per document that actually contains a mermaid diagram
/// (the Reader creates it lazily, gated on [treeContainsMermaid] — a
/// document without one must not pay for a hidden webview it never
/// uses, mirroring the visible webview engine's own lazy-controller
/// rule). [attach] MUST be mounted somewhere in the widget tree (even
/// invisibly) for the underlying platform webview to actually load and
/// run JavaScript at all.
///
/// Render requests are serialized through a JavaScript channel
/// (`MermaidResult`) rather than `runJavaScriptReturningResult`, since
/// the latter does not reliably hand back an awaited Promise's
/// resolved value across every webview_flutter platform backend.
class MermaidBridge {
  MermaidBridge({required this._renderer});

  /// The offscreen controller — exposed so [attach] can host it.
  final WebViewController controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted);

  final DocRenderer _renderer;

  Future<bool>? _loading;
  int _nextRequestId = 0;
  final Map<String, Completer<MermaidRenderResult>> _pending = {};

  /// Loads `mermaid.js` + `mermaid-bridge.js` into the controller's page
  /// exactly once (subsequent calls reuse the same in-flight/completed
  /// attempt). Returns false — never throws — when the assets can't be
  /// fetched (no reachable `libmdviewer`) or the page fails to load; a
  /// host without a native library must degrade to the diagram
  /// placeholder, not crash.
  Future<bool> _ensureLoaded() => _loading ??= _load();

  Future<bool> _load() async {
    try {
      final mermaidJs = utf8.decode(_renderer.asset('mermaid.js'));
      final bridgeJs = utf8.decode(_renderer.asset('mermaid-bridge.js'));
      controller.addJavaScriptChannel(
        'MermaidResult',
        onMessageReceived: _handleMessage,
      );
      await controller.loadHtmlString(
        '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
        '<body><script>$mermaidJs</script><script>$bridgeJs</script>'
        '</body></html>',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Renders [source] (one diagram's Mermaid source) to SVG. [id] should
  /// be the render tree's `Diagram.ID` (unique per document, HTML-id
  /// safe); [theme] one of mermaid's theme names (`'default'`/`'dark'`/
  /// etc.). Never throws — every failure resolves to
  /// `MermaidRenderResult.failure(...)`, including a timeout (10s) if
  /// the page never calls back.
  Future<MermaidRenderResult> render({
    required String id,
    required String source,
    required String theme,
  }) async {
    final ready = await _ensureLoaded();
    if (!ready) {
      return MermaidRenderResult.failure('mermaid bridge unavailable');
    }
    final requestId = 'r${_nextRequestId++}';
    final completer = Completer<MermaidRenderResult>();
    _pending[requestId] = completer;
    final script =
        'mdvRenderMermaid(${jsonEncode(id)}, ${jsonEncode(source)}, '
        '${jsonEncode(theme)}).then(function(r) { '
        'r.requestId = ${jsonEncode(requestId)}; '
        'MermaidResult.postMessage(JSON.stringify(r)); '
        '});';
    try {
      await controller.runJavaScript(script);
    } catch (e) {
      _pending.remove(requestId);
      return MermaidRenderResult.failure('$e');
    }
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(requestId);
        return MermaidRenderResult.failure(
          'timed out waiting for mermaid render',
        );
      },
    );
  }

  void _handleMessage(JavaScriptMessage message) {
    try {
      final map = jsonDecode(message.message) as Map<String, dynamic>;
      final requestId = map['requestId'] as String?;
      final completer = requestId == null ? null : _pending.remove(requestId);
      if (completer == null || completer.isCompleted) return;
      if (map['ok'] == true) {
        completer.complete(
          MermaidRenderResult.success(map['svg'] as String? ?? ''),
        );
      } else {
        completer.complete(
          MermaidRenderResult.failure(
            map['error'] as String? ?? 'unknown error',
          ),
        );
      }
    } catch (_) {
      // A malformed payload leaves its completer pending — [render]'s
      // own timeout resolves it instead of hanging forever.
    }
  }

  /// The offscreen widget hosting the bridge's webview. MUST be mounted
  /// (even invisibly, as here) for the platform webview to load and run
  /// JavaScript at all — never shown to the user.
  Widget attach() => Offstage(
    offstage: true,
    child: SizedBox(
      width: 1,
      height: 1,
      child: WebViewWidget(controller: controller),
    ),
  );
}
