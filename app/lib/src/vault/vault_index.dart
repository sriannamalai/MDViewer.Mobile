import 'vault_entry.dart';
import 'vault_source.dart';

/// Builds a vault's Library tree from a flat list of Markdown-file relative
/// paths — what the platform channels (and [SampleVaultProvider]) hand back
/// from `list()`. Pure and synchronous, independent of any provider or
/// platform I/O, so it's the one piece of "index" logic that's fully
/// unit-tested without a device or a fake channel.
///
/// Rules (design/README.md §01 + MDViewer.Desktop's `read_dir_tree`, which
/// this mirrors):
/// - Folders first, then files; both alphabetical, case-insensitive, at
///   every level.
/// - Each directory's [VaultEntry.mdCount] is the recursive count of
///   Markdown files anywhere in its subtree (Desktop's sidebar badge).
///
/// Directories are inferred purely from path prefixes — a directory with no
/// Markdown file anywhere in its subtree never appears; that matches "index
/// = Markdown files" from the vault design. Non-Markdown paths (images) are
/// intentionally never passed in here — they're read on demand via
/// `VaultState.resolveRelative` instead of being part of the index.
class VaultIndex {
  const VaultIndex._();

  /// [mdRelPaths] need not be pre-sorted or deduplicated. A path repeated
  /// verbatim collapses to a single leaf entry.
  static List<VaultEntry> build(List<String> mdRelPaths, VaultSource source) {
    final root = _DirNode();
    for (final raw in mdRelPaths) {
      final segments = raw.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) continue;
      var node = root;
      for (var i = 0; i < segments.length - 1; i++) {
        node = node.dirs.putIfAbsent(segments[i], () => _DirNode());
      }
      node.files.add(segments.last);
    }
    return _entriesFor(root, '', source);
  }

  static List<VaultEntry> _entriesFor(
    _DirNode node,
    String prefix,
    VaultSource source,
  ) {
    final dirNames = node.dirs.keys.toList()..sort(_ciCompare);
    final fileNames = node.files.toSet().toList()..sort(_ciCompare);

    final dirEntries = dirNames.map((name) {
      final child = node.dirs[name]!;
      final childPrefix = prefix.isEmpty ? name : '$prefix/$name';
      return VaultEntry(
        name: name,
        relPath: childPrefix,
        isDir: true,
        children: _entriesFor(child, childPrefix, source),
        source: source,
        mdCount: _mdCount(child),
      );
    });

    final fileEntries = fileNames.map((name) {
      final fullPath = prefix.isEmpty ? name : '$prefix/$name';
      return VaultEntry(
        name: name,
        relPath: fullPath,
        isDir: false,
        children: const [],
        source: source,
      );
    });

    return [...dirEntries, ...fileEntries];
  }

  static int _mdCount(_DirNode node) {
    var count = node.files.toSet().length;
    for (final child in node.dirs.values) {
      count += _mdCount(child);
    }
    return count;
  }

  static int _ciCompare(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}

class _DirNode {
  final Map<String, _DirNode> dirs = {};
  final List<String> files = [];
}
