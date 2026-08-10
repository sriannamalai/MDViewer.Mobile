import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/screens/reader.dart';
import 'src/screens/splash_gate.dart';
import 'src/state/app_state.dart';
import 'src/state/vault_state.dart';
import 'src/tokens.dart';
import 'src/vault/open_with_channel.dart';
import 'src/vault/open_with_delivery_queue.dart';

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
/// side's cold/warm handshake this depends on, and
/// [OpenWithDeliveryQueue]'s for why a not-yet-mounted [_navigatorKey] on
/// cold start queues and retries rather than dropping the delivery.
class MDViewerApp extends StatefulWidget {
  const MDViewerApp({super.key});

  @override
  State<MDViewerApp> createState() => _MDViewerAppState();
}

class _MDViewerAppState extends State<MDViewerApp> {
  final AppState _appState = AppState();
  final VaultState _vaultState = VaultState();
  final OpenWithChannel _openWith = OpenWithChannel();
  final OpenWithDeliveryQueue _openWithQueue = OpenWithDeliveryQueue();
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
    _routeOpenWithFile(file);
  }

  /// Queues [file] and attempts delivery via [_openWithQueue] — the root
  /// [Navigator] not being mounted yet (a cold "Open with" launch racing
  /// the very first frame) queues it for a bounded number of retries on
  /// later frames instead of silently dropping it. Once the Navigator is
  /// ready, [_pushOpenWithFile] does the actual push for every queued file.
  void _routeOpenWithFile(OpenWithFile file) {
    _openWithQueue.add(file);
    _drainOpenWithQueue();
  }

  void _drainOpenWithQueue() {
    _openWithQueue.drain(
      isReady: () => _navigatorKey.currentState != null,
      deliver: (file) => unawaited(_pushOpenWithFile(file)),
      scheduleRetry: (retry) {
        WidgetsBinding.instance.addPostFrameCallback((_) => retry());
        // Guarantees a next frame actually happens even if the app is
        // otherwise fully idle (no animation, no pending setState) — an
        // addPostFrameCallback registered with nothing else scheduling a
        // frame could otherwise wait indefinitely for something unrelated
        // to trigger one.
        WidgetsBinding.instance.scheduleFrame();
      },
    );
  }

  Future<void> _pushOpenWithFile(OpenWithFile file) async {
    final navigator = _navigatorKey.currentState;
    // isReady() just confirmed this; belt-and-suspenders.
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
