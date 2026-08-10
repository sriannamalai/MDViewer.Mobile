import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  VaultState({VaultProvider? sampleProvider, VaultProvider? folderProvider})
    : _sampleProvider = sampleProvider ?? const SampleVaultProvider(),
      _folderProvider = folderProvider ?? PlatformVaultProvider();

  static const _recentsKey = 'vault.recents';
  static const _grantKey = 'vault.grant';

  final VaultProvider _sampleProvider;
  final VaultProvider _folderProvider;

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

  /// [VaultSource.openedFile] is a data-model placeholder for the "Open
  /// with" single-file flow — its read path is wired up in the search /
  /// open-with task. Routing it through the folder provider here is a
  /// harmless default: it's only exercised once that task registers the
  /// open-with intent/URL handlers and starts producing `openedFile`
  /// entries.
  VaultProvider _providerFor(VaultSource source) {
    switch (source) {
      case VaultSource.sample:
        return _sampleProvider;
      case VaultSource.folder:
      case VaultSource.openedFile:
        return _folderProvider;
    }
  }

  /// Looks up a previously-indexed entry by vault-relative path (used for
  /// e.g. resolving an internal `.md` link to a Reader push). Returns null
  /// if [source]'s tree hasn't been indexed yet or doesn't contain
  /// [relPath].
  VaultEntry? findByRelPath(VaultSource source, String relPath) {
    final index = source == VaultSource.sample ? _sampleFlat : _folderFlat;
    return index[relPath];
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
