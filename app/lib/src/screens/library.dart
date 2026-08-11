import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:provider/provider.dart';

import '../navigation.dart';
import '../state/vault_state.dart';
import '../tokens.dart';
import '../util/relative_time.dart';
import '../vault/recent_entry.dart';
import '../vault/vault_entry.dart';
import '../widgets/file_row.dart';
import '../widgets/library_header.dart';
import '../widgets/library_search_field.dart';

/// The Library screen — design/README.md §01: header, search field (a
/// navigation affordance to the Search tab, not a real text field here),
/// the vault folder's tree (when a folder grant exists), the always-present
/// bundled Samples tree, and a Recent section once at least one document
/// has been opened. Renders a "Choose folder" prompt in place of the vault
/// section when no folder has been picked yet.
///
/// [onOpenSearch] is the tab-switch hook `AppShell` (Task 3) wires up — this
/// screen never owns tab-bar state itself.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final Set<String> _expandedKeys = {};
  bool _picking = false;
  String? _pickError;

  static String _key(VaultEntry entry) =>
      '${entry.source.name}:${entry.relPath}';

  bool _isExpanded(VaultEntry entry) => _expandedKeys.contains(_key(entry));

  void _toggleExpanded(VaultEntry entry) {
    setState(() {
      final key = _key(entry);
      if (!_expandedKeys.remove(key)) _expandedKeys.add(key);
    });
  }

  bool _isActive(VaultEntry entry, RecentEntry? mostRecent) {
    if (mostRecent == null) return false;
    return entry.relPath == mostRecent.relPath &&
        entry.source == mostRecent.source;
  }

  /// Prompts for a folder via [VaultState.pickFolder], guarding against a
  /// second concurrent call (the native side's own "busy" guard — see
  /// `ios/Runner/VaultChannel.swift` — still throws if this races it, e.g.
  /// a fast double-tap before the first `setState` lands) and surfacing any
  /// failure as a dismissible banner rather than letting the exception
  /// propagate into a crash.
  Future<void> _handleChooseFolder(VaultState vault) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _pickError = null;
    });
    try {
      await vault.pickFolder();
    } catch (error) {
      if (mounted) setState(() => _pickError = _describePickError(error));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String _describePickError(Object error) {
    if (error is PlatformException && error.code == 'busy') {
      return 'Already choosing a folder — try again in a moment.';
    }
    return "Couldn't add that folder. Try again.";
  }

  /// Pushes the Reader for [entry] — no pre-read here. `ReaderScreen._load`
  /// reads the document itself (recording it in Recents) and owns error
  /// surfacing; a pre-read would double every open over the platform
  /// channel and, if it threw (file vanished, unreadable SAF entry), kill
  /// the tap handler unhandled before the Reader's error UI could show it.
  Future<void> _openFile(VaultEntry entry) => pushReader(context, entry);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final vault = context.watch<VaultState>();
    final mostRecent = vault.recents.isEmpty ? null : vault.recents.first;
    final hasVault = vault.grant != null;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onSearchTap: widget.onOpenSearch),
            if (_pickError != null)
              _ErrorBanner(
                message: _pickError!,
                onDismiss: () => setState(() => _pickError = null),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: [
                  if (!hasVault)
                    _EmptyVaultPrompt(
                      busy: _picking,
                      onChooseFolder: () => _handleChooseFolder(vault),
                    )
                  else
                    _TreeSection(
                      label: vault.vaultName!,
                      topPadding: 10,
                      entries: vault.entries,
                      isExpanded: _isExpanded,
                      onToggle: _toggleExpanded,
                      onTapFile: _openFile,
                      isActive: (entry) => _isActive(entry, mostRecent),
                    ),
                  _TreeSection(
                    label: 'Samples',
                    topPadding: hasVault ? 18 : 10,
                    entries: vault.sampleEntries,
                    isExpanded: _isExpanded,
                    onToggle: _toggleExpanded,
                    onTapFile: _openFile,
                    isActive: (entry) => _isActive(entry, mostRecent),
                  ),
                  if (vault.recents.isNotEmpty)
                    _RecentSection(
                      recents: vault.recents,
                      vault: vault,
                      mostRecent: mostRecent,
                      onTapFile: _openFile,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The panel-surfaced header block: icon/wordmark/theme-toggle row plus the
/// search field beneath it, both padded and framed exactly as
/// design/README.md §01 describes ("white `panel`, 1px `line` bottom
/// border").
class _Header extends StatelessWidget {
  const _Header({required this.onSearchTap});

  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          children: [
            const LibraryHeader(),
            const SizedBox(height: 14),
            LibrarySearchField(onTap: onSearchTap),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.topPadding});

  final String label;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topPadding, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: AppFonts.ibmPlexSans,
          fontSize: AppTypeScale.librarySectionLabelSize,
          fontWeight: AppTypeScale.librarySectionLabelWeight,
          letterSpacing: AppTypeScale.librarySectionLabelLetterSpacing,
          color: tokens.text3,
        ),
      ),
    );
  }
}

/// One tree section: an uppercase label plus the [entries] tree, rendered
/// via [VaultTreeRow] at depth 0.
class _TreeSection extends StatelessWidget {
  const _TreeSection({
    required this.label,
    required this.topPadding,
    required this.entries,
    required this.isExpanded,
    required this.onToggle,
    required this.onTapFile,
    required this.isActive,
  });

  final String label;
  final double topPadding;
  final List<VaultEntry> entries;
  final bool Function(VaultEntry entry) isExpanded;
  final void Function(VaultEntry entry) onToggle;
  final void Function(VaultEntry entry) onTapFile;
  final bool Function(VaultEntry entry) isActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: label, topPadding: topPadding),
        for (final entry in entries)
          VaultTreeRow(
            entry: entry,
            depth: 0,
            isExpanded: isExpanded,
            onToggle: onToggle,
            onTapFile: onTapFile,
            isActive: isActive,
          ),
      ],
    );
  }
}

/// The flat "Recent" section — each row resolved from a [RecentEntry] back
/// to its [VaultEntry] (for the name/badge) via [VaultState.findByRelPath],
/// with relative-time meta instead of the tree's "›" chevron. A recent
/// entry whose backing file has since vanished from its vault's index
/// (deleted, or a stale sample-vault reference) is silently skipped rather
/// than crashing the row build.
class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.recents,
    required this.vault,
    required this.mostRecent,
    required this.onTapFile,
  });

  final List<RecentEntry> recents;
  final VaultState vault;
  final RecentEntry? mostRecent;
  final void Function(VaultEntry entry) onTapFile;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final rows = <Widget>[];
    for (final recent in recents) {
      final entry = vault.findByRelPath(recent.source, recent.relPath);
      if (entry == null) continue;
      rows.add(
        LibraryFileRow(
          entry: entry,
          depth: 0,
          active: recent == mostRecent,
          onTap: () => onTapFile(entry),
          trailing: Text(
            RelativeTime.format(
              DateTime.fromMillisecondsSinceEpoch(recent.openedAtMs),
            ),
            style: TextStyle(
              fontFamily: AppFonts.jetBrainsMono,
              fontSize: AppTypeScale.libraryRowMetaSize,
              color: tokens.text3,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Recent', topPadding: 18),
        ...rows,
      ],
    );
  }
}

/// The empty-vault prompt shown in place of the folder-vault tree section
/// when no folder has been picked/restored yet — tokens-styled per the task
/// brief ("Empty vault state (no grant): tokens-styled prompt + 'Choose
/// folder' button"). The Samples section still renders below this
/// regardless, so the app is never literally empty.
class _EmptyVaultPrompt extends StatelessWidget {
  const _EmptyVaultPrompt({required this.busy, required this.onChooseFolder});

  final bool busy;
  final VoidCallback onChooseFolder;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(AppGeometry.radiusLibraryRow),
      ),
      child: Column(
        children: [
          Text(
            'No folder added',
            style: TextStyle(
              fontFamily: AppFonts.sourceSerif4,
              fontSize: AppTypeScale.h3Size,
              fontWeight: AppTypeScale.h3Weight,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a folder to browse its Markdown files here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.ibmPlexSans,
              fontSize: AppTypeScale.bodySize,
              color: tokens.text2,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: AppGeometry.minTapTarget,
            child: ElevatedButton(
              onPressed: busy ? null : onChooseFolder,
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.panel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppGeometry.radiusButtonMax,
                  ),
                ),
              ),
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.panel,
                      ),
                    )
                  : const Text('Choose folder'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tokens-styled dismissible banner for a failed [VaultState.pickFolder]
/// call — "surfaces as a snackbar-equivalent tokens-styled banner, not a
/// crash" per the task brief, covering both the native "busy" guard and any
/// other platform-channel failure.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  // Genuinely one-off: this banner (and its ✕ glyph) isn't in the design
  // reference at all, so the size is undesigned and deliberately NOT an
  // AppTypeScale token.
  static const double _dismissGlyphSize = 13;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      width: double.infinity,
      color: tokens.accentSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: AppFonts.ibmPlexSans,
                fontSize: AppTypeScale.uiTextSize,
                color: tokens.accent,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Text(
              '✕',
              style: TextStyle(
                fontSize: _dismissGlyphSize,
                color: tokens.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
