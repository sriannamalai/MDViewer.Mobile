/// Pure path arithmetic for the vault's `/`-separated relative paths — no
/// platform I/O, no VaultEntry dependency. The one function here
/// ([resolve]) is what makes `VaultState.resolveRelative` (the reader's
/// image resolver, Task 5) safe: it turns an authored relative link
/// (`img/logo.png`, `../shared/x.png`) into a vault-root-relative path
/// *without* ever being able to walk above the vault root.
class VaultPath {
  const VaultPath._();

  /// Resolves [relPath] (as authored in a Markdown link/image target, e.g.
  /// `img/logo.png` or `../shared/x.png`) against the directory containing
  /// [fromRelPath] (the vault-relative path of the document doing the
  /// linking).
  ///
  /// Returns the resolved vault-relative path, or null if:
  /// - [relPath] is empty,
  /// - [relPath] looks absolute (starts with `/` — an authored `/etc/passwd`
  ///   is rejected outright rather than reinterpreted as vault-root-relative),
  /// - or the resolution would walk above the vault root (a `..` with
  ///   nothing left on the stack to pop).
  ///
  /// Existence of the resolved path is NOT checked here — that's a provider
  /// read, done by the caller.
  static String? resolve(String fromRelPath, String relPath) {
    if (relPath.isEmpty || relPath.startsWith('/')) return null;

    final dir = _dirname(fromRelPath);
    final segments = <String>[
      if (dir.isNotEmpty) ...dir.split('/'),
      ...relPath.split('/'),
    ];

    final stack = <String>[];
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (stack.isEmpty) return null; // would escape the vault root
        stack.removeLast();
      } else {
        stack.add(segment);
      }
    }
    if (stack.isEmpty) return null;
    return stack.join('/');
  }

  static String _dirname(String relPath) {
    final slash = relPath.lastIndexOf('/');
    return slash < 0 ? '' : relPath.substring(0, slash);
  }
}
