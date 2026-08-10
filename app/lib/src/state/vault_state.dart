import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../vault/opened_file_vault_provider.dart';
import '../vault/platform_vault_provider.dart';
import '../vault/recent_entry.dart';
import '../vault/recents_store.dart';
import '../vault/sample_vault_provider.dart';
import '../vault/vault_entry.dart';
import '../vault/vault_grant.dart';
import '../vault/vault_index.dart';
import '../vault/vault_path.dart';
import '../vault/vault_provider.dart';
import '../vault/vault_source.dart';

/// The app's single source of truth for "what documents exist and where".
///
/// Owns both always-present content (the bundled sample vault) and the
/// at-most-one user-picked folder vault, plus Recents. Screens (Library,
/// Reader, Search) read [entries]/[sampleEntries]/[recents] and call
/// [pickFolder]/[readDoc]/[resolveRelative]; nothing above this layer talks
/// to a [VaultProvider] or `shared_preferences` directly.
///
/// [entries] is the current folder vault's tree (empty until a folder is
/// picked or a persisted grant is restored); [sampleEntries] is always
/// populated once [init] completes — the Library screen renders them as
/// separate sections (design/README.md §01: vault label = folder name,
/// SAMPLES section, RECENT section).
class VaultState extends ChangeNotifier {
  VaultState({
    VaultProvider? sampleProvider,
    VaultProvider? folderProvider,
    OpenedFileVaultProvider? openedFileProvider,
  }) : _sampleProvider = sampleProvider ?? const SampleVaultProvider(),
       _folderProvider = folderProvider ?? PlatformVaultProvider(),
       _openedFileProvider = openedFileProvider ?? OpenedFileVaultProvider();

  static const _recentsKey = 'vault.recents';
  static const _grantKey = 'vault.grant';

  final VaultProvider _sampleProvider;
  final VaultProvider _folderProvider;
  final OpenedFileVaultProvider _openedFileProvider;

  bool _ready = false;
  bool get ready => _ready;

  List<VaultEntry> _sampleEntries = const [];
  List<VaultEntry> get sampleEntries => _sampleEntries;

  List<VaultEntry> _entries = const [];
  List<VaultEntry> get entries => _entries;

  VaultGrant? _grant;
  VaultGrant? get grant => _grant;

  /// The active folder vault's display name (design's "vault label"), or
  /// null when no folder has been picked/restored yet.
  String? get vaultName => _grant?.displayName;

  List<RecentEntry> _recents = const [];
  List<RecentEntry> get recents => _recents;

  final Map<String, VaultEntry> _sampleFlat = {};
  final Map<String, VaultEntry> _folderFlat = {};

  /// Loads recents, the bundled sample vault, and (if one was persisted and
  /// still resolves) the last folder grant. Must be awaited before the
  /// splash screen dismisses to Library (Task 3) — [ready] flips true only
  /// once this completes, matching the spec's "dismisses when the vault
  /// index is ready".
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    final recentsRaw = prefs.getString(_recentsKey);
    _recents = recentsRaw == null ? const [] : RecentsStore.decode(recentsRaw);

    final sampleList = await _sampleProvider.list(SampleVaultProvider.grant);
    _sampleEntries = VaultIndex.build(sampleList, VaultSource.sample);
    _sampleFlat
      ..clear()
      ..addAll(_flatten(_sampleEntries));

    // Guarded the same way RecentsStore.decode guards recents: a corrupt
    // (not just wrong-shape, but unparseable) persisted grant blob must
    // degrade to "no grant" rather than throwing out of init().
    VaultGrant? savedGrant;
    try {
      final grantRaw = prefs.getString(_grantKey);
      savedGrant = grantRaw == null
          ? null
          : VaultGrant.fromJson(jsonDecode(grantRaw));
    } catch (_) {
      savedGrant = null;
    }
    if (savedGrant != null) {
      final restored = await _folderProvider.restore(savedGrant);
      if (restored) {
        _grant = savedGrant;
        await _reloadFolderEntries();
      } else {
        // Stale bookmark / revoked permission: drop the persisted grant so
        // the Library screen falls back to its empty-vault "Choose folder"
        // prompt instead of silently retrying a dead grant on every launch.
        await prefs.remove(_grantKey);
      }
    }

    _ready = true;
    notifyListeners();
  }

  /// Prompts the user to pick a folder via the native picker. Returns false
  /// if the user cancelled (nothing changes); true once the new grant is
  /// persisted and its entries are loaded.
  Future<bool> pickFolder() async {
    final grant = await _folderProvider.pickFolder();
    if (grant == null) return false;

    _grant = grant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_grantKey, jsonEncode(grant.toJson()));
    await _reloadFolderEntries();
    notifyListeners();
    return true;
  }

  Future<void> _reloadFolderEntries() async {
    final grant = _grant;
    if (grant == null) return;
    final list = await _folderProvider.list(grant);
    _entries = VaultIndex.build(list, VaultSource.folder);
    _folderFlat
      ..clear()
      ..addAll(_flatten(_entries));
  }

  Map<String, VaultEntry> _flatten(List<VaultEntry> nodes) {
    final out = <String, VaultEntry>{};
    void walk(VaultEntry entry) {
      out[entry.relPath] = entry;
      for (final child in entry.children) {
        walk(child);
      }
    }

    for (final node in nodes) {
      walk(node);
    }
    return out;
  }

  VaultProvider _providerFor(VaultSource source) {
    switch (source) {
      case VaultSource.sample:
        return _sampleProvider;
      case VaultSource.folder:
        return _folderProvider;
      case VaultSource.openedFile:
        return _openedFileProvider;
    }
  }

  /// Registers a single OS "Open with MDViewer" file (design/README.md's
  /// open-with note; `vault/open_with_channel.dart`) as a
  /// [VaultSource.openedFile] entry and returns it, ready to push to the
  /// Reader. Replaces any previously opened single file — v1 holds at most
  /// one at a time, matching the desktop/folder vaults' own "one grant"
  /// rule.
  ///
  /// No folder grant backs this entry, so [resolveRelative] always
  /// declines for it — [OpenedFileVaultProvider]'s doc comment covers why
  /// (the documented v1 limitation: relative images/links don't resolve
  /// for files opened this way).
  VaultEntry openSingleFile({required String name, required Uint8List bytes}) {
    _openedFileProvider.setFile(name: name, bytes: bytes);
    final entry = VaultEntry(
      name: name,
      relPath: name,
      isDir: false,
      children: const [],
      source: VaultSource.openedFile,
    );
    _openedFileEntry = entry;
    return entry;
  }

  /// The entry [openSingleFile] most recently registered, or null before
  /// any "Open with" delivery this app run — [findByRelPath]'s only source
  /// of truth for [VaultSource.openedFile] lookups (there is no flattened
  /// index for it the way [_sampleFlat]/[_folderFlat] back the other two
  /// sources, since it's never more than one file).
  VaultEntry? _openedFileEntry;

  /// Looks up a previously-indexed entry by vault-relative path (used for
  /// e.g. resolving an internal `.md` link, or a Recent row, back to a
  /// pushable [VaultEntry]). Returns null if [source]'s tree hasn't been
  /// indexed yet (or, for [VaultSource.openedFile], no file has been
  /// registered / a *different* file has since replaced it) or doesn't
  /// contain [relPath].
  ///
  /// [VaultSource.openedFile] is handled explicitly rather than falling
  /// into the folder-tree lookup: an open-with document was never indexed
  /// into [_folderFlat] (or any tree at all — [openSingleFile] doesn't
  /// touch [_entries]), so routing it there either misses forever (the
  /// Library's Recent row for it would silently occupy a capped slot doing
  /// nothing) or — worse — collides with an unrelated same-named file that
  /// genuinely does live in the folder vault, resolving to the wrong
  /// document on tap.
  VaultEntry? findByRelPath(VaultSource source, String relPath) {
    switch (source) {
      case VaultSource.sample:
        return _sampleFlat[relPath];
      case VaultSource.folder:
        return _folderFlat[relPath];
      case VaultSource.openedFile:
        final entry = _openedFileEntry;
        return (entry != null && entry.relPath == relPath) ? entry : null;
    }
  }

  /// Reads [entry]'s bytes and records the open in Recents (moved to the
  /// front, capped at 8, persisted).
  Future<Uint8List> readDoc(VaultEntry entry) async {
    final bytes = await _providerFor(entry.source).read(entry);

    _recents = RecentsStore.add(
      _recents,
      RecentEntry(
        relPath: entry.relPath,
        source: entry.source,
        openedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentsKey, RecentsStore.encode(_recents));
    notifyListeners();

    return bytes;
  }

  /// Reads [entry]'s bytes *without* touching Recents — the search
  /// engine's read hook (`vault/search.dart`'s `VaultSearch.search`).
  /// Scanning a file while searching isn't "opening" it, so it must not
  /// show up in the Library's Recent section the way [readDoc] deliberately
  /// does for an actual Reader open.
  Future<Uint8List> readRaw(VaultEntry entry) =>
      _providerFor(entry.source).read(entry);

  /// Resolves an authored relative link/image target ([relPath], e.g.
  /// `img/logo.png`) against [from]'s directory and reads its bytes — the
  /// reader's image resolver's one call into the vault layer.
  ///
  /// Never throws: returns null for a path that would escape the vault
  /// root ([VaultPath.resolve]'s traversal guard), doesn't exist, or fails
  /// to read for any other reason. The resolver's job on a null is to fall
  /// back to "no image", not to propagate an exception into the render
  /// pipeline.
  Future<Uint8List?> resolveRelative(VaultEntry from, String relPath) async {
    final resolved = VaultPath.resolve(from.relPath, relPath);
    if (resolved == null) return null;

    final slash = resolved.lastIndexOf('/');
    final name = slash < 0 ? resolved : resolved.substring(slash + 1);
    final target = VaultEntry(
      name: name,
      relPath: resolved,
      isDir: false,
      children: const [],
      source: from.source,
    );

    try {
      return await _providerFor(from.source).read(target);
    } catch (_) {
      return null;
    }
  }
}
