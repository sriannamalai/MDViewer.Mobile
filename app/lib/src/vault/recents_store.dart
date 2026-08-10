import 'dart:convert';

import 'recent_entry.dart';
import 'vault_source.dart';

/// Recents list rules (cap 8, dedupe-then-push-front) and the
/// shared_preferences JSON codec, sanitized field-by-field on load so a
/// corrupt/hand-edited/older-version blob degrades to a clean empty list
/// instead of crashing app boot — the same lesson MDViewer.Desktop's
/// `appstate.ts` documents ("`sanitize()` never throws").
class RecentsStore {
  const RecentsStore._();

  static const int cap = 8;

  /// Moves-or-pushes [entry] to the front of [existing], deduped by
  /// identity (`relPath` + `source` — desktop's `addRecent` rule, extended
  /// with `source` since this app has more than one vault), capped at
  /// [cap]. Returns a new list; [existing] is not mutated.
  static List<RecentEntry> add(List<RecentEntry> existing, RecentEntry entry) {
    final deduped = existing
        .where((e) => !(e.relPath == entry.relPath && e.source == entry.source))
        .toList();
    deduped.insert(0, entry);
    if (deduped.length > cap) deduped.removeRange(cap, deduped.length);
    return deduped;
  }

  static String encode(List<RecentEntry> recents) =>
      jsonEncode(recents.map((e) => e.toJson()).toList());

  /// Parses a persisted JSON string into a sanitized recents list. Any
  /// exception during JSON decoding (corrupt/truncated text, not just a
  /// wrong shape) falls back to an empty list rather than throwing —
  /// "corrupt prefs JSON never crashes boot" from the task brief.
  static List<RecentEntry> decode(String raw) {
    try {
      return sanitize(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  /// Narrows an arbitrary parsed-JSON value into a valid recents list.
  /// A non-list top level degrades to an empty list; an individual item
  /// that isn't a well-formed entry (missing/empty `relPath`, or a
  /// `source` that isn't one of [VaultSource]'s names) is dropped rather
  /// than defaulted, since there's no safe default source to fabricate.
  /// `openedAtMs` does get a default (0) when missing/invalid, since any
  /// non-negative timestamp is a safe fallback. The result is capped at
  /// [cap] the same as [add].
  static List<RecentEntry> sanitize(Object? raw) {
    if (raw is! List) return const [];
    final out = <RecentEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final relPath = item['relPath'];
      if (relPath is! String || relPath.isEmpty) continue;
      final source = _sourceFromName(item['source']);
      if (source == null) continue;
      out.add(
        RecentEntry(
          relPath: relPath,
          source: source,
          openedAtMs: _clampedInt(item['openedAtMs']),
        ),
      );
    }
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  static VaultSource? _sourceFromName(Object? name) {
    if (name is! String) return null;
    for (final source in VaultSource.values) {
      if (source.name == name) return source;
    }
    return null;
  }

  static int _clampedInt(Object? value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is double && value.isFinite) return value < 0 ? 0 : value.round();
    return 0;
  }
}
