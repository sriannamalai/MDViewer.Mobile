import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/screens/splash_gate.dart';
import 'src/state/app_state.dart';
import 'src/state/vault_state.dart';
import 'src/tokens.dart';

void main() {
  runApp(const MDViewerApp());
}

/// App root: wires [AppState] (theme + text scale) and [VaultState]
/// (documents) as providers, then hands off to [SplashGate] — splash until
/// the vault index is ready, then the tab-bar shell (`src/screens/
/// shell.dart`).
class MDViewerApp extends StatefulWidget {
  const MDViewerApp({super.key});

  @override
  State<MDViewerApp> createState() => _MDViewerAppState();
}

class _MDViewerAppState extends State<MDViewerApp> {
  final AppState _appState = AppState();
  final VaultState _vaultState = VaultState();

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: AppState's pre-load defaults (system theme, 1.0 text
    // scale) are safe to render immediately; init() swaps in whatever was
    // persisted (if anything) and notifies once it resolves. VaultState's
    // init() is intentionally *not* started here — SplashGate owns it, since
    // its completion is what dismisses the splash.
    unawaited(_appState.init());
  }

  @override
  void dispose() {
    _appState.dispose();
    _vaultState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<VaultState>.value(value: _vaultState),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          return MaterialApp(
            title: 'MDViewer.Mobile',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: appState.themeMode,
            home: SplashGate(vaultState: _vaultState),
          );
        },
      ),
    );
  }
}
