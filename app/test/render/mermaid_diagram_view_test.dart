import 'package:app/src/render/mermaid_bridge.dart';
import 'package:app/src/render/mermaid_diagram_view.dart';
import 'package:app/src/render/renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/mdviewer.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_webview_platform.dart';

/// A [MermaidBridge] whose [render] is faked (never touches the real
/// offscreen webview) but records every `theme` argument it was called
/// with, in call order — the seam issue #7's fix (re-render on a theme
/// flip) is asserted through.
class _RecordingMermaidBridge extends MermaidBridge {
  _RecordingMermaidBridge() : super(renderer: DocRenderer());

  final List<String> themes = [];

  @override
  Future<MermaidRenderResult> render({
    required String id,
    required String source,
    required String theme,
  }) async {
    themes.add(theme);
    return MermaidRenderResult.success('<svg>$theme</svg>');
  }
}

const _node = MdvDiagram(
  id: 'd1',
  source: 'graph TD; A-->B;',
  engine: 'mermaid',
);

Widget _host(Brightness brightness, MermaidBridge? bridge) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.light),
    darkTheme: ThemeData(brightness: Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: MermaidDiagramView(
        node: _node,
        bridge: bridge,
        fallback: const Text('fallback'),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // MermaidBridge's `controller` field constructs a real
    // WebViewController even though [_RecordingMermaidBridge] never lets
    // it load anything — a platform must still be registered for that
    // construction to succeed under `flutter test`.
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  testWidgets('renders once at first build, themed for the ambient '
      'brightness', (tester) async {
    final bridge = _RecordingMermaidBridge();
    await tester.pumpWidget(_host(Brightness.light, bridge));
    await tester.pumpAndSettle();

    expect(bridge.themes, ['default']);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('a theme flip after first render re-invokes the bridge with '
      'the new theme (issue #7)', (tester) async {
    final bridge = _RecordingMermaidBridge();
    await tester.pumpWidget(_host(Brightness.light, bridge));
    await tester.pumpAndSettle();
    expect(bridge.themes, ['default']);

    await tester.pumpWidget(_host(Brightness.dark, bridge));
    await tester.pumpAndSettle();

    expect(
      bridge.themes,
      ['default', 'dark'],
      reason:
          'the diagram must re-render with the flipped theme, not keep '
          'its first-render colors until the document reopens',
    );
  });

  testWidgets('an unrelated rebuild at the SAME brightness does not '
      're-render (no request storm on every frame)', (tester) async {
    final bridge = _RecordingMermaidBridge();
    await tester.pumpWidget(_host(Brightness.light, bridge));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(Brightness.light, bridge));
    await tester.pumpAndSettle();

    expect(bridge.themes, ['default']);
  });

  testWidgets('a null bridge (no mermaid in this document) always shows the '
      'fallback, never touches the bridge', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, null));
    await tester.pumpAndSettle();

    expect(find.text('fallback'), findsOneWidget);
  });
}
