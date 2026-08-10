import 'dart:typed_data';

import 'vault_entry.dart';
import 'vault_grant.dart';
import 'vault_provider.dart';

/// The in-memory [VaultProvider] behind [VaultSource.openedFile] — v1's OS
/// "Open with MDViewer" single-file flow (see `open_with_channel.dart` and
/// `VaultState.openSingleFile`). Holds at most one file at a time (the most
/// recently opened); nothing here is persisted across app restarts — a
/// fresh cold "Open with" launch always re-delivers the file from the OS
/// side, so there's nothing to restore.
///
/// This is *why* a document opened this way never resolves sibling images:
/// [read] only ever recognizes the one currently-held file. Any other
/// relative path a `VaultState.resolveRelative` call asks for throws, which
/// the caller (the reader's resolver) already treats as "decline" — no
/// special-casing needed anywhere else. That's the documented v1 limitation
/// for open-with docs (task-7-report.md): the platform grant is the file
/// itself, not its folder, so there IS no sibling to read.
class OpenedFileVaultProvider implements VaultProvider {
  String? _name;
  Uint8List? _bytes;

  void setFile({required String name, required Uint8List bytes}) {
    _name = name;
    _bytes = bytes;
  }

  @override
  Future<VaultGrant?> pickFolder() => throw UnsupportedError(
    'OpenedFileVaultProvider does not support picking a folder.',
  );

  @override
  Future<bool> restore(VaultGrant grant) async => false;

  @override
  Future<List<String>> list(VaultGrant grant) async =>
      _name == null ? const [] : [_name!];

  @override
  Future<Uint8List> read(VaultEntry entry) async {
    final bytes = _bytes;
    if (bytes == null || entry.relPath != _name) {
      throw StateError(
        'OpenedFileVaultProvider.read: no open file matches "${entry.relPath}"',
      );
    }
    return bytes;
  }
}
