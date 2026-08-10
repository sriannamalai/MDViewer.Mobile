import 'package:flutter/material.dart';

import 'src/tokens.dart';

void main() {
  runApp(const MDViewerApp());
}

/// App root. Real navigation (Library/Reader/Search/Settings) lands in
/// later tasks — this is a minimal, tokens-styled placeholder that proves
/// [AppTheme]/[AppTokens] wire up correctly end to end.
class MDViewerApp extends StatelessWidget {
  const MDViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDViewer.Mobile',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      body: Center(
        child: Text(
          'MarkDownViewer',
          style: TextStyle(
            fontFamily: AppFonts.sourceSerif4,
            fontSize: AppTypeScale.h1Size,
            fontWeight: AppTypeScale.h1Weight,
            color: tokens.text,
          ),
        ),
      ),
    );
  }
}
