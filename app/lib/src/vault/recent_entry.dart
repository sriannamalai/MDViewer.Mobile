import 'vault_source.dart';

/// One row of the Library screen's "Recent" section: which document, from
/// which source, opened when. Immutable — `RecentsStore` produces new lists
/// rather than mutating entries in place.
class RecentEntry {
  const RecentEntry({
    required this.relPath,
    required this.source,
    required this.openedAtMs,
  });

  final String relPath;
  final VaultSource source;

  /// Epoch milliseconds (`DateTime.now().millisecondsSinceEpoch`).
  final int openedAtMs;

  Map<String, dynamic> toJson() => {
    'relPath': relPath,
    'source': source.name,
    'openedAtMs': openedAtMs,
  };

  @override
  bool operator ==(Object other) =>
      other is RecentEntry &&
      other.relPath == relPath &&
      other.source == source &&
      other.openedAtMs == openedAtMs;

  @override
  int get hashCode => Object.hash(relPath, source, openedAtMs);

  @override
  String toString() => 'RecentEntry($relPath, $source, $openedAtMs)';
}
