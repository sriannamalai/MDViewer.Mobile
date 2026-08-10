import 'package:flutter/material.dart';

import '../state/vault_state.dart';
import 'shell.dart';
import 'splash.dart';

/// Owns the splash-vs-shell decision: shows [SplashScreen] until
/// [VaultState.init] completes (folders-first, then samples, per
/// design/README.md §00 — "Dismisses to Library when the vault index is
/// ready") *and* at least [minDisplay] has elapsed, so a fast/cached init
/// doesn't flash the splash for a single frame. Once both conditions hold,
/// swaps to [AppShell].
///
/// [vaultState] is injected (rather than pulled from `Provider` internally)
/// so widget tests can pump a fake/instrumented [VaultState] without a real
/// platform channel or asset bundle behind it.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.vaultState,
    this.minDisplay = const Duration(milliseconds: 600),
  });

  final VaultState vaultState;
  final Duration minDisplay;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _showShell = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    if (!widget.vaultState.ready) {
      await widget.vaultState.init();
    }

    final elapsed = DateTime.now().difference(started);
    final remaining = widget.minDisplay - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }

    if (!mounted) return;
    setState(() => _showShell = true);
  }

  @override
  Widget build(BuildContext context) {
    return _showShell ? const AppShell() : const SplashScreen();
  }
}
