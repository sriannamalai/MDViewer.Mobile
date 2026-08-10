/// Formats the interval between [from] and "now" as the short relative-time
/// strings design/README.md §01's Recent section shows next to each row
/// ("2h", "1d") — mono meta text, same size/color role as the vault tree's
/// folder child-count meta.
///
/// Bucketed at whole units (minutes, hours, days, ...) rather than rounded,
/// matching the everyday reading of "2h ago" style labels. Never negative in
/// the output, even when [from] is slightly in the future relative to [now]
/// (clock skew, or a persisted `openedAtMs` racing the read that produced
/// it) — that clamps to `'now'` instead of surfacing a negative duration.
class RelativeTime {
  const RelativeTime._();

  /// [now] defaults to [DateTime.now] — overridable so callers (and tests)
  /// can pin the reference instant instead of depending on wall-clock time.
  static String format(DateTime from, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(from);

    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo';
    return '${diff.inDays ~/ 365}y';
  }
}
