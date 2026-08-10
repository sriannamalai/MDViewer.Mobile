// Minimal smoke test for the Task 1 scaffold: the app builds and renders
// its tokens-styled placeholder home without throwing. Real screen tests
// land alongside their screens in later tasks.

import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  testWidgets('MDViewerApp builds and shows the placeholder home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MDViewerApp());

    expect(find.text('MarkDownViewer'), findsOneWidget);
  });
}
