import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/screens/reader.dart';
import 'src/screens/splash_gate.dart';
import 'src/state/app_state.dart';
import 'src/state/vault_state.dart';
import 'src/tokens.dart';
import 'src/vault/open_with_channel.dart';

void main() {
  runApp(const MDViewerApp());
}

/// App root: wires [AppState] (theme + text scale) and [VaultState]
/// (documents) as providers, then hands off to [SplashGate] — splash until
/// the vault index is ready, then the tab-bar shell (`src/screens/
/// shell.dart`).
///
/// Also owns the OS "Open with MDViewer" wiring
/// (`src/vault/open_with_channel.dart`): [_navigatorKey] lets a warm
/// delivery push the Reader from outside any particular screen's
/// [BuildContext] (the platform channel's callback fires whenever the OS
/// hands over a new file, regardless of what's currently on screen), and
/// [_consumeInitialOpenWithFile] handles the cold-start case (the app was
/// launched *by* opening a file) the same way, just pulled once at startup
/// instead of pushed. See `OpenWithChannel`'s doc comment for the native
/// side's cold/warm handshake this depends on.
class MDViewerApp extends StatefulWidget {
  const MDViewerApp({super.key});

  @override
  State<MDViewerApp> createState() => _MDViewerAppState();
}

class _MDViewerAppState extends State<MDViewerApp> {
  final AppState _appState = AppState();
  final VaultState _vaultState = VaultState();
  final OpenWithChannel _openWith = OpenWithChannel();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: AppState's pre-load defaults (system theme, 1.0 text
    // scale) are safe to render immediately; init() swaps in whatever was
    // persisted (if anything) and notifies once it resolves. VaultState's
    // init() is intentionally *not* started here — SplashGate owns it, since
    // its completion is what dismisses the splash.
    unawaited(_appState.init());

    // Registered before the initial-file pull so a file delivered *between*
    // that pull and this call (a vanishingly unlikely but possible race) is
    // still caught by the warm-delivery path rather than silently dropped.
    _openWith.listen(_routeOpenWithFile);
    unawaited(_consumeInitialOpenWithFile());
  }

  Future<void> _consumeInitialOpenWithFile() async {
    final file = await _openWith.takeInitialFile();
    if (file == null) return;
    await _routeOpenWithFile(file);
  }

  /// Pushes the Reader for [file] via [_navigatorKey] — best-effort: if the
  /// root [Navigator] isn't mounted yet (a cold "Open with" launch racing
  /// the very first frame), the delivery is silently dropped rather than
  /// queued for retry. In practice the platform-channel round trip alone
  /// takes at least one event-loop turn, which is enough for `MaterialApp`
  /// to have mounted; a device-level check that this never actually races
  /// is Task 8's job, not something worth complicating this method for.
  Future<void> _routeOpenWithFile(OpenWithFile file) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    final entry = _vaultState.openSingleFile(
      name: file.name,
      bytes: file.bytes,
    );
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(entry: entry)),
    );
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
            navigatorKey: _navigatorKey,
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
