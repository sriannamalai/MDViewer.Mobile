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
/// One render request per THEME [didChangeDependencies] observes:
/// re-invoking [MermaidBridge.render] on every rebuild would re-run the
/// offscreen bridge for no reason (an Aa text-scale step, a hierarchy
/// rebuild that doesn't touch brightness at all), so the request is
/// cached and reused exactly like every other native block's "styled at
/// build time" contract — UNTIL the ambient brightness actually flips,
/// at which point [_renderedDark] no longer matches and a fresh request
/// is issued with the new mermaid `theme` argument. This closes the gap
/// the class doc used to carry (a diagram kept its original light/dark
/// colors until the document was reopened) — every other native block
/// already restyles in place on a theme flip; a diagram now does too, at
/// the cost of one extra offscreen render per flip while a mermaid
/// document is open.
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

  /// The brightness [_future]'s in-flight/completed request was issued
  /// for — null until the first request. Compared against the CURRENT
  /// brightness on every [didChangeDependencies] call (which Flutter
  /// invokes whenever an ancestor `Theme`/`MediaQuery` this widget reads
  /// changes, not just on first build) so a theme flip is the only thing
  /// that triggers a re-render; an Aa step or unrelated rebuild leaves a
  /// same-brightness request untouched.
  bool? _renderedDark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bridge = widget.bridge;
    if (bridge == null) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_future != null && dark == _renderedDark) return;
    _renderedDark = dark;
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
