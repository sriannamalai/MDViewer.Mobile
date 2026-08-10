/// Derives the filename the Reader's share sheet writes the rendered,
/// self-contained HTML to — design/README.md's "share ⇪ exports ... self-
/// contained HTML". A pure string transform (no `dart:io`) so it's testable
/// without a temp directory.
class ShareFilename {
  const ShareFilename._();

  static final RegExp _mdExtension = RegExp(
    r'\.(md|markdown)$',
    caseSensitive: false,
  );

  // Conservative filesystem-safe allowlist: letters, digits, space, dot,
  // underscore, hyphen. Everything else (path separators, control
  // characters, emoji, quotes, ...) becomes '_' rather than being dropped,
  // so two differently-named-but-similarly-unsafe files don't collide.
  static final RegExp _unsafe = RegExp(r'[^A-Za-z0-9 ._-]');

  /// Turns a `VaultEntry.name` (e.g. `"Getting Started.md"`) into the share
  /// file's name (`"Getting Started.html"`): the `.md`/`.markdown`
  /// extension replaced with `.html`, unsafe characters replaced with `_`,
  /// leading dots stripped (a name that started with a dot would otherwise
  /// produce a hidden file on most platforms — surprising for a share-sheet
  /// export), and a `"document"` fallback for a name that sanitizes to
  /// nothing (e.g. an original name that was ONLY unsafe characters).
  static String forEntryName(String name) {
    final withoutExtension = name.replaceFirst(_mdExtension, '');
    var sanitized = withoutExtension.replaceAll(_unsafe, '_').trim();
    while (sanitized.startsWith('.')) {
      sanitized = sanitized.substring(1);
    }
    if (sanitized.isEmpty) sanitized = 'document';
    return '$sanitized.html';
  }
}
