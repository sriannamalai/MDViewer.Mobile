import 'dart:typed_data';

import 'vault_entry.dart';
import 'vault_grant.dart';

/// Abstraction over "a place documents live" — the bundled asset bundle, or
/// a user-granted folder reached through a platform channel (iOS
/// security-scoped bookmarks, Android SAF).
///
/// `VaultState` is the only caller. Everything above it (screens, search,
/// the reader's resolver) talks to `VaultState`, never a provider directly
/// — which is what lets unit tests substitute a fake provider for the real
/// platform-channel ones without touching a device. The channel
/// implementations (`PlatformVaultProvider` + the iOS/Android native sides)
/// are exercised end-to-end on-device in a later task; this interface is
/// what keeps that boundary clean.
abstract class VaultProvider {
  /// Prompts the user to choose a folder (a native folder picker) and
  /// returns the resulting grant, or null if the user cancelled. A
  /// provider that doesn't support picking (the bundled sample vault) may
  /// throw [UnsupportedError] — `VaultState` never calls this on those.
  Future<VaultGrant?> pickFolder();

  /// Lists every Markdown file reachable from [grant]'s root — depth-bounded,
  /// dotfiles/dot-directories skipped (see the platform channel docs) — as a
  /// flat list of vault-relative paths. Order is unspecified; `VaultIndex`
  /// does the sorting/nesting.
  Future<List<String>> list(VaultGrant grant);

  /// Reads the raw bytes at [entry]'s vault-relative path. Throws if the
  /// path doesn't exist, isn't readable, or names a directory.
  ///
  /// Deliberately takes no [VaultGrant]: a provider only ever has one grant
  /// active at a time (v1 non-goal — multiple vaults), tracked as the
  /// provider's own state by whichever of [pickFolder]/[restore]/[list]
  /// activated it last.
  Future<Uint8List> read(VaultEntry entry);

  /// Re-establishes access to a previously persisted [grant]: resolving an
  /// iOS security-scoped bookmark and starting its scope, or re-validating
  /// an Android persisted URI permission. Returns false for a
  /// stale/revoked grant — `VaultState`'s response to `false` is to drop
  /// the persisted grant and fall back to prompting again via
  /// [pickFolder], never to retry blindly.
  Future<bool> restore(VaultGrant grant);
}
