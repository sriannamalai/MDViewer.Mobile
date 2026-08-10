import 'vault_source.dart';

/// One node in a vault's Library tree.
///
/// Directories carry [children] (folders-first, alphabetical — see
/// [VaultIndex.build]) and [mdCount], the number of `.md`/`.markdown` files
/// anywhere in their subtree (recursive — mirrors MDViewer.Desktop's
/// sidebar file-count badge). Files have no children and an [mdCount] of 0.
///
/// [relPath] is always `/`-separated and relative to the vault root
/// regardless of platform — it's the identity used for persistence
/// (recents), lookups, and [VaultPath.resolve].
class VaultEntry {
  const VaultEntry({
    required this.name,
    required this.relPath,
    required this.isDir,
    required this.children,
    required this.source,
    this.mdCount = 0,
  });

  final String name;
  final String relPath;
  final bool isDir;
  final List<VaultEntry> children;
  final VaultSource source;
  final int mdCount;

  static final RegExp _mdExtension = RegExp(
    r'\.(md|markdown)$',
    caseSensitive: false,
  );

  /// Whether this is a Markdown file by extension (`.md`/`.markdown`,
  /// case-insensitive) — always false for directories.
  bool get isMarkdown => !isDir && _mdExtension.hasMatch(name);

  @override
  String toString() => 'VaultEntry($relPath, isDir: $isDir, source: $source)';
}
