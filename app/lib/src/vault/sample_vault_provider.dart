import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'vault_entry.dart';
import 'vault_grant.dart';
import 'vault_provider.dart';

/// The bundled sample vault — always present, asset-backed, no platform
/// channel involved. Ships under `app/assets/samples/`: one rich doc
/// (`Welcome.md` — mermaid, KaTeX inline/block, a Go code fence, a relative
/// image, a wiki-link, a task list), a couple of lighter docs, and a
/// `Notes/` subfolder, per the vault design.
///
/// [mdRelPaths] is the single source of truth for which Markdown files ship
/// — kept in sync by hand with `pubspec.yaml`'s asset declarations and the
/// files actually on disk (deliberately not derived from
/// `AssetManifest.json`: that manifest is a build artifact, and pinning the
/// list here means `list()` is synchronous-fast and the sample-vault unit
/// test catches drift immediately if a file gets renamed without updating
/// this list — see the task-2 report for the tradeoff).
///
/// Non-Markdown assets (the bundled `img/logo.png`) are intentionally not
/// listed — they're read on demand through [read] via
/// `VaultState.resolveRelative`, exactly like the real folder providers.
class SampleVaultProvider implements VaultProvider {
  const SampleVaultProvider();

  static const String assetRoot = 'assets/samples/';

  /// The sample vault's grant is a fixed, non-persisted placeholder —
  /// `VaultState` never saves or restores it; it's only a valid argument to
  /// [list]/[restore].
  static const VaultGrant grant = VaultGrant(
    id: 'sample',
    displayName: 'Samples',
  );

  static const List<String> mdRelPaths = [
    'Welcome.md',
    'Getting Started.md',
    'Colophon.md',
    'Notes/Ideas.md',
    'Notes/Project Plan.md',
  ];

  @override
  Future<VaultGrant?> pickFolder() => throw UnsupportedError(
    'SampleVaultProvider does not support picking a folder — it is always present.',
  );

  @override
  Future<bool> restore(VaultGrant grant) async => true;

  @override
  Future<List<String>> list(VaultGrant grant) async => mdRelPaths;

  @override
  Future<Uint8List> read(VaultEntry entry) async {
    final data = await rootBundle.load('$assetRoot${entry.relPath}');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
