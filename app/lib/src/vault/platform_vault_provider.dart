import 'package:flutter/services.dart';

import 'vault_entry.dart';
import 'vault_grant.dart';
import 'vault_provider.dart';

/// The real, on-device [VaultProvider] for user-picked folders — talks to
/// the native side over the `mdviewer/vault` `MethodChannel` (iOS:
/// `ios/Runner/VaultChannel.swift`; Android:
/// `android/.../VaultChannel.kt`). `VaultState` is the only caller in this
/// app; tests exercise the vault/state layer against a fake provider
/// instead — the channel's actual folder-access behavior is device-only and
/// covered by manual/E2E verification (see the task-2 report), not by
/// `flutter test`.
///
/// Only one grant is active per provider instance at a time (v1 non-goal:
/// multiple vaults — see the spec). [read] has no grant parameter (per the
/// [VaultProvider] contract), so it operates against whichever grant
/// [pickFolder]/[restore]/[list] most recently activated — tracked here as
/// [_activeGrantId].
///
/// Wire protocol (method name → arguments → result):
/// - `pickFolder` → (none) → `{id, displayName}` map, or null if cancelled.
/// - `restore` → `{id}` → bool.
/// - `list` → `{id}` → `List<String>` of vault-relative Markdown paths.
/// - `read` → `{id, relPath}` → raw bytes, or a `PlatformException` if the
///   path doesn't resolve.
class PlatformVaultProvider implements VaultProvider {
  PlatformVaultProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('mdviewer/vault');

  final MethodChannel _channel;
  String? _activeGrantId;

  @override
  Future<VaultGrant?> pickFolder() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickFolder',
    );
    if (result == null) return null; // user cancelled the native picker
    final grant = VaultGrant.fromJson(result);
    if (grant == null) return null;
    _activeGrantId = grant.id;
    return grant;
  }

  @override
  Future<bool> restore(VaultGrant grant) async {
    final ok =
        await _channel.invokeMethod<bool>('restore', {'id': grant.id}) ?? false;
    if (ok) _activeGrantId = grant.id;
    return ok;
  }

  @override
  Future<List<String>> list(VaultGrant grant) async {
    _activeGrantId = grant.id;
    final result = await _channel.invokeListMethod<String>('list', {
      'id': grant.id,
    });
    return result ?? const [];
  }

  @override
  Future<Uint8List> read(VaultEntry entry) async {
    final grantId = _activeGrantId;
    if (grantId == null) {
      throw StateError(
        'PlatformVaultProvider.read: no active grant — call pickFolder()/restore() first',
      );
    }
    final bytes = await _channel.invokeMethod<Uint8List>('read', {
      'id': grantId,
      'relPath': entry.relPath,
    });
    if (bytes == null) {
      throw StateError(
        'PlatformVaultProvider.read: native side returned nothing for "${entry.relPath}"',
      );
    }
    return bytes;
  }
}
