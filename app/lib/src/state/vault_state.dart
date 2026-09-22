import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../vault/opened_file_vault_provider.dart';
import '../vault/platform_vault_provider.dart';
import '../vault/recent_entry.dart';
import '../vault/recents_store.dart';
import '../vault/sample_vault_provider.dart';
import '../vault/search.dart' show VaultSearch;
import '../vault/vault_entry.dart';
import '../vault/vault_grant.dart';
import '../vault/vault_index.dart';
import '../vault/vault_path.dart';
import '../vault/vault_provider.dart';
import '../vault/vault_source.dart';

/// The app's single source of truth for "what documents exist and where".
///
/// Owns both always-present content (the bundled sample vault) and a LIST
/// of user-picked folder vaults (issue #9 — v1's original design allowed
/// only one at a time), plus Recents. Screens (Library, Reader, Search)
/// read [entries]/[sampleEntries]/[recents] and call
/// [pickFolder]/[readDoc]/[resolveRelative]; nothing above this layer talks
/// to a [VaultProvider] or `shared_preferences` directly.
///
/// [entries] is always the ACTIVE folder vault's tree (empty until a
/// folder is picked, or none restores); [sampleEntries] is always
/// populated once [init] completes — the Library screen renders them as
/// separate sections (design/README.md §01: vault label = folder name,
/// SAMPLES section, RECENT section).
///
/// ## Multi-vault design (issue #9)
///
/// [vaultGrants] persists every folder the user has ever picked; exactly
/// one of them (or none) is ACTIVE at a time ([activeGrantId]/[grant]).
/// [VaultProvider]'s own contract (see its class doc) only ever holds ONE
/// grant's native access active at a time — an iOS security-scoped
/// bookmark's `startAccessingSecurityScopedResource()` call, an Android
/// SAF permission check — so [switchVault] re-runs [VaultProvider.restore]
/// for whichever grant becomes active, exactly like [init] does for the
/// persisted active grant at cold start. [entries]/[VaultSource.folder]
/// lookups ([findByRelPath], [resolveRelative], [markdownRelPaths]) are
/// therefore always scoped to whichever vault is CURRENTLY active — a
/// [VaultEntry] resolved from a non-active vault (e.g. an older Recent
/// row) won't resolve again until its vault is made active. Broadening
/// [VaultEntry]/[VaultSource] to carry a per-instance vault id (so every
/// vault's tree could be Browse-able and resolvable simultaneously) would
/// be a materially larger change than this issue's own "reasonably-scoped
/// version" framing calls for; this is the pragmatic middle ground.
///
/// Persists as [_grantsKey] (a JSON array of [VaultGrant]s) +
/// [_activeGrantIdKey] (which one is active). [init] migrates a v1
/// single-grant install (the old [_legacyGrantKey]) into this shape
/// exactly once, so an existing user's one folder survives the upgrade as
/// a one-item, active vault list.
class VaultState extends ChangeNotifier {
  VaultState({
    VaultProvider? sampleProvider,
    VaultProvider? folderProvider,
    OpenedFileVaultProvider? openedFileProvider,
  }) : _sampleProvider = sampleProvider ?? const SampleVaultProvider(),
       _folderProvider = folderProvider ?? PlatformVaultProvider(),
       _openedFileProvider = openedFileProvider ?? OpenedFileVaultProvider();

  static const _recentsKey = 'vault.recents';

  /// v1's single-grant key — read once, at [init], to migrate an existing
  /// install onto [_grantsKey]; never written again after that.
  static const _legacyGrantKey = 'vault.grant';

  /// The persisted list of every folder vault the user has picked (issue
  /// #9), as a JSON array of [VaultGrant.toJson] objects.
  static const _grantsKey = 'vault.grants';

  /// Which of [_grantsKey]'s entries (by [VaultGrant.id]) is active, or
  /// absent when none is (no vaults, or the active one failed to restore
  /// and nothing else could take its place).
  static const _activeGrantIdKey = 'vault.activeGrantId';

  final VaultProvider _sampleProvider;
  final VaultProvider _folderProvider;
  final OpenedFileVaultProvider _openedFileProvider;

  bool _ready = false;
  bool get ready => _ready;

  List<VaultEntry> _sampleEntries = const [];
  List<VaultEntry> get sampleEntries => _sampleEntries;

  List<VaultEntry> _entries = const [];
  List<VaultEntry> get entries => _entries;

  List<VaultGrant> _vaultGrants = const [];

  /// Every folder vault the user has picked, in the order they were added
  /// — the Library screen's vault switcher lists these (issue #9).
  List<VaultGrant> get vaultGrants => _vaultGrants;

  String? _activeGrantId;

  /// The [VaultGrant.id] of the currently active folder vault, or null.
  String? get activeGrantId => _activeGrantId;

  /// The currently ACTIVE folder vault's grant, or null when none is
  /// active. Kept as the pre-#9 API surface (`grant`/`vaultName`) so
  /// every existing caller (Reader's vault label, Library's `hasVault`
  /// check) keeps working unchanged — they only ever cared about "the one
  /// folder vault", which is now "whichever one is active".
  VaultGrant? get grant => _grantById(_activeGrantId);

  /// The active folder vault's display name (design's "vault label"), or
  /// null when no folder is active.
  String? get vaultName => grant?.displayName;

  List<RecentEntry> _recents = const [];
  List<RecentEntry> get recents => _recents;

  final Map<String, VaultEntry> _sampleFlat = {};
  final Map<String, VaultEntry> _folderFlat = {};

  VaultGrant? _grantById(String? id) {
    if (id == null) return null;
    for (final g in _vaultGrants) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Loads recents, the bundled sample vault, every persisted folder-vault
  /// grant, and (if the active one still resolves) its entries. Must be
  /// awaited before the splash screen dismisses to Library (Task 3) —
  /// [ready] flips true only once this completes, matching the spec's
  /// "dismisses when the vault index is ready".
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    final recentsRaw = prefs.getString(_recentsKey);
    _recents = recentsRaw == null ? const [] : RecentsStore.decode(recentsRaw);

    final sampleList = await _sampleProvider.list(SampleVaultProvider.grant);
    _sampleEntries = VaultIndex.build(sampleList, VaultSource.sample);
    _sampleFlat
      ..clear()
      ..addAll(_flatten(_sampleEntries));

    _loadVaultGrants(prefs);

    // Try the active grant first; if it fails to restore (stale bookmark /
    // revoked permission), drop it and fall through to the next one, same
    // "never retry a dead grant blindly" posture v1 had — just extended to
    // "try the rest of the list" instead of "give up entirely".
    var candidate = _grantById(_activeGrantId);
    while (candidate != null) {
      if (await _folderProvider.restore(candidate)) {
        _activeGrantId = candidate.id;
        await _reloadFolderEntries(candidate);
        break;
      }
      _vaultGrants = _vaultGrants.where((g) => g.id != candidate!.id).toList();
      _activeGrantId = null;
      candidate = _vaultGrants.isEmpty ? null : _vaultGrants.first;
    }

    await _persistVaultGrants(prefs);
    if (prefs.containsKey(_legacyGrantKey)) await prefs.remove(_legacyGrantKey);

    _ready = true;
    notifyListeners();
  }

  /// Populates [_vaultGrants]/[_activeGrantId] from [_grantsKey] if
  /// present; otherwise migrates a v1 single-grant install from
  /// [_legacyGrantKey] (making it the sole, active vault). A corrupt/
  /// unparseable value under either key degrades to "no vaults" — the
  /// same defensive posture v1's single-grant load had — rather than
  /// throwing out of [init].
  void _loadVaultGrants(SharedPreferences prefs) {
    try {
      final grantsRaw = prefs.getString(_grantsKey);
      if (grantsRaw != null) {
        final decoded = jsonDecode(grantsRaw);
        if (decoded is List) {
          _vaultGrants = [for (final item in decoded) ?VaultGrant.fromJson(item)];
        }
        _activeGrantId = prefs.getString(_activeGrantIdKey);
        return;
      }

      final legacyRaw = prefs.getString(_legacyGrantKey);
      if (legacyRaw != null) {
        final migrated = VaultGrant.fromJson(jsonDecode(legacyRaw));
        if (migrated != null) {
          _vaultGrants = [migrated];
          _activeGrantId = migrated.id;
        }
      }
    } catch (_) {
      _vaultGrants = const [];
      _activeGrantId = null;
    }
  }

  Future<void> _persistVaultGrants(SharedPreferences prefs) async {
    await prefs.setString(
      _grantsKey,
      jsonEncode(_vaultGrants.map((g) => g.toJson()).toList()),
    );
    final activeId = _activeGrantId;
    if (activeId == null) {
      await prefs.remove(_activeGrantIdKey);
    } else {
      await prefs.setString(_activeGrantIdKey, activeId);
    }
  }

  /// Prompts the user to pick a folder via the native picker and ADDS it
  /// to [vaultGrants] (issue #9 — v1 replaced the single grant; this
  /// keeps every previously-picked vault too), making the new one active.
  /// Returns false if the user cancelled (nothing changes); true once the
  /// new grant is persisted and its entries are loaded. Re-picking a
  /// folder the app already has a grant for (same [VaultGrant.id])
  /// replaces that entry in place rather than duplicating it.
  Future<bool> pickFolder() async {
    final grant = await _folderProvider.pickFolder();
    if (grant == null) return false;

    _vaultGrants = [
      ..._vaultGrants.where((g) => g.id != grant.id),
      grant,
    ];
    _activeGrantId = grant.id;
    await _reloadFolderEntries(grant);

    final prefs = await SharedPreferences.getInstance();
    await _persistVaultGrants(prefs);
    notifyListeners();
    return true;
  }

  /// Switches the active folder vault to [grantId] (issue #9's Library
  /// switcher): re-[VaultProvider.restore]s its native access (the
  /// provider only ever holds one grant's access active — see the class
  /// doc), reloads its entries, and persists the new active id. Returns
  /// false — leaving the PREVIOUS vault active, unchanged — when
  /// [grantId] isn't in [vaultGrants] or its restore fails (a revoked/
  /// stale grant is NOT dropped here, unlike [init]'s cold-start pass — a
  /// user explicitly tapping a vault that briefly fails to restore
  /// shouldn't lose it from the list; [removeVault] is the explicit,
  /// deliberate way to drop one).
  Future<bool> switchVault(String grantId) async {
    if (grantId == _activeGrantId) return true;
    final target = _grantById(grantId);
    if (target == null) return false;

    if (!await _folderProvider.restore(target)) return false;

    _activeGrantId = grantId;
    await _reloadFolderEntries(target);

    final prefs = await SharedPreferences.getInstance();
    await _persistVaultGrants(prefs);
    notifyListeners();
    return true;
  }

  /// Removes [grantId] from [vaultGrants] (issue #9's Library switcher).
  /// If it was the active vault, automatically activates the next
  /// remaining one (if any restores) so removing one vault doesn't
  /// silently blank the Library's folder section when others are still
  /// configured; falls back to "no active vault" (the empty-vault prompt)
  /// if none remain or none restores. There's no native "revoke" call
  /// ([VaultProvider] exposes none) — the OS-side grant simply becomes
  /// unused, the same as v1 replacing a grant always implicitly did.
  Future<void> removeVault(String grantId) async {
    final wasActive = grantId == _activeGrantId;
    _vaultGrants = _vaultGrants.where((g) => g.id != grantId).toList();

    if (wasActive) {
      _activeGrantId = null;
      _entries = const [];
      _folderFlat.clear();
      for (final candidate in _vaultGrants) {
        if (await _folderProvider.restore(candidate)) {
          _activeGrantId = candidate.id;
          await _reloadFolderEntries(candidate);
          break;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await _persistVaultGrants(prefs);
    notifyListeners();
  }

  Future<void> _reloadFolderEntries(VaultGrant grant) async {
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

  /// Every Markdown file's vault-relative path in [source]'s tree —
  /// vault-WIDE, not scoped to any one document's directory. The
  /// wiki-link resolver (`render/wiki_link.dart`, issue #10) matches a
  /// `[[...]]` target against exactly this list, for the SAME vault the
  /// linking document lives in (a folder-vault document's wiki-links
  /// never resolve against the bundled Samples, and vice versa).
  /// [VaultSource.openedFile] has no tree at all — [_openedFileEntry] is
  /// at most one file — so it always returns empty: an "Open with"
  /// document's wiki-links have nothing to resolve against, the same
  /// posture as its unresolved relative links/images (issue #8).
  List<String> markdownRelPaths(VaultSource source) {
    switch (source) {
      case VaultSource.sample:
        return [
          for (final e in VaultSearch.flattenMarkdownFiles(_sampleEntries))
            e.relPath,
        ];
      case VaultSource.folder:
        return [
          for (final e in VaultSearch.flattenMarkdownFiles(_entries)) e.relPath,
        ];
      case VaultSource.openedFile:
        return const [];
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
