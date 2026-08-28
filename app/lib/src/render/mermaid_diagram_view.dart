import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mdviewer/mdviewer.dart';

import 'mermaid_bridge.dart';

/// The native engine's `mermaid` diagram builder (`MdvBuilders.diagram`):
/// renders [node]'s source to SVG via [bridge] and displays it with
/// `flutter_svg`, falling back to [fallback] (the library's placeholder
/// box — engine label + mono source) while loading, on any render
/// failure, or if [bridge] is null (no mermaid diagram was detected in
/// this document, so no offscreen webview was ever created — see
/// `mermaid_bridge.dart`'s class doc).
///
/// One render request per widget lifetime: [didChangeDependencies] fires
/// it at most once (guarded by [_future]), so an Aa/theme rebuild reuses
/// the cached request instead of re-rendering the same diagram — the
/// request's theme is fixed at first build, matching every other native
/// block's "styled at build time, not re-rendered" contract EXCEPT that
/// a THEME FLIP after the diagram already rendered keeps its original
/// light/dark colors until the document is reopened; an acceptable
/// first-cut gap (documented in the app README) rather than added
/// complexity for a rare mid-read theme change.
class MermaidDiagramView extends StatefulWidget {
  const MermaidDiagramView({
    super.key,
    required this.node,
    required this.bridge,
    required this.fallback,
  });

  final MdvDiagram node;
  final MermaidBridge? bridge;
  final Widget fallback;

  @override
  State<MermaidDiagramView> createState() => _MermaidDiagramViewState();
}

class _MermaidDiagramViewState extends State<MermaidDiagramView> {
  Future<MermaidRenderResult>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bridge = widget.bridge;
    if (bridge == null || _future != null) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    _future = bridge.render(
      id: widget.node.id,
      source: widget.node.source,
      theme: dark ? 'dark' : 'default',
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) return widget.fallback;
    return FutureBuilder<MermaidRenderResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.fallback;
        }
        final result = snapshot.data;
        final svg = result?.svg;
        if (result == null || !result.ok || svg == null) return widget.fallback;
        return SvgPicture.string(
          svg,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => widget.fallback,
        );
      },
    );
  }
}
