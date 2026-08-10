import 'dart:convert';
import 'dart:typed_data';

import 'vault_entry.dart';

/// The three independent filter toggles design/README.md §04 shows as
/// pills ("Aa / .* / Whole word"): case-sensitive matching, treat the query
/// as a regular expression, and match whole words only. All default off —
/// the §04 screenshot happens to show "Aa" active, but that's one example
/// state, not a documented default; a fresh Search screen starts
/// case-insensitive/literal/substring, the least surprising default for a
/// "search my notes" field.
class SearchFilters {
  const SearchFilters({
    this.caseSensitive = false,
    this.regex = false,
    this.wholeWord = false,
  });

  final bool caseSensitive;
  final bool regex;
  final bool wholeWord;

  SearchFilters copyWith({bool? caseSensitive, bool? regex, bool? wholeWord}) {
    return SearchFilters(
      caseSensitive: caseSensitive ?? this.caseSensitive,
      regex: regex ?? this.regex,
      wholeWord: wholeWord ?? this.wholeWord,
    );
  }
}

/// One matched line — design/README.md §04's result card: [entry] + 1-based
/// [line], and a [snippet] (a trimmed window of the source line, capped to
/// [VaultSearch.snippetWindow] chars) with [matchStart]/[matchEnd] byte
/// offsets *into that snippet* (not into the original line) marking the
/// substring the card renders in `accent`.
class SearchMatch {
  const SearchMatch({
    required this.entry,
    required this.line,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
  });

  final VaultEntry entry;
  final int line;
  final String snippet;
  final int matchStart;
  final int matchEnd;
}

/// The outcome of a [VaultSearch.search] call: either a (possibly empty,
/// possibly [capped]) list of [matches], or an [error] message when
/// [SearchFilters.regex] was on and the query didn't compile — mutually
/// exclusive ([error] non-null implies [matches] is empty).
class SearchResult {
  const SearchResult({
    required this.matches,
    required this.fileCount,
    required this.capped,
    this.error,
  });

  static const SearchResult empty = SearchResult(
    matches: [],
    fileCount: 0,
    capped: false,
  );

  final List<SearchMatch> matches;

  /// Number of distinct files represented in [matches] — design's "N
  /// results in M files" count line. Only counts files among the
  /// (possibly capped) returned matches, matching the count line the user
  /// actually sees.
  final int fileCount;

  /// True once [VaultSearch.resultCap] was hit and the scan stopped early —
  /// the count line's "(showing first N)" note.
  final bool capped;

  /// Non-null only for an invalid [SearchFilters.regex] pattern — the
  /// screen's inline error state. The engine never throws for this; a bad
  /// pattern is data, not an exception.
  final String? error;
}

/// The vault-wide search engine behind design/README.md §04. Pure Dart, no
/// platform/provider dependency of its own — [search]'s [readBytes]
/// callback is how the Search screen supplies file content (via
/// `VaultState.readRaw`, which — unlike `readDoc` — does *not* touch
/// Recents; a search shouldn't mark every scanned file "recently opened").
class VaultSearch {
  const VaultSearch._();

  /// Design's "result cap (e.g. 200, capped note in count line)".
  static const int resultCap = 200;

  /// Target snippet length in characters — the match is centered in this
  /// window where the line has enough content on both sides, otherwise the
  /// window shifts toward whichever side has room (see [_snippet]).
  static const int snippetWindow = 90;

  /// Searches every file in [entries] (directories/non-Markdown entries are
  /// skipped defensively; callers normally pass an already-flattened
  /// Markdown-only list from [flattenMarkdownFiles]) for [query] under
  /// [filters].
  ///
  /// Chunked across files: yields to the event loop between each file
  /// (`await Future<void>.delayed(Duration.zero)`) and checks
  /// [isCancelled] before starting each new file, so a caller whose query
  /// changed mid-scan (a newer [search] call bumping its own generation
  /// counter) can actually interrupt a long-running older one instead of
  /// racing it to `setState`. A file already being read when cancellation
  /// happens still has its matches counted — the read's cost is already
  /// sunk, so discarding that work would just waste it. A cancelled scan
  /// returns whatever it found so far — the caller is expected to discard
  /// it, not display it.
  ///
  /// An empty (or all-whitespace-stripped-to-empty — trimming is the
  /// caller's job, not this engine's) [query] returns [SearchResult.empty]
  /// immediately, no file reads. An invalid [SearchFilters.regex] pattern
  /// returns a [SearchResult] with [SearchResult.error] set instead of
  /// throwing — never propagates a [FormatException] to the caller.
  static Future<SearchResult> search({
    required String query,
    required List<VaultEntry> entries,
    required Future<Uint8List> Function(VaultEntry entry) readBytes,
    SearchFilters filters = const SearchFilters(),
    bool Function()? isCancelled,
  }) async {
    if (query.isEmpty) return SearchResult.empty;

    final RegExp matcher;
    try {
      matcher = _buildMatcher(query, filters);
    } on FormatException catch (error) {
      return SearchResult(
        matches: const [],
        fileCount: 0,
        capped: false,
        error: error.message.isEmpty ? 'Invalid pattern' : error.message,
      );
    }

    bool cancelled() => isCancelled?.call() ?? false;

    final matches = <SearchMatch>[];
    final filesMatched = <String>{};
    var capped = false;

    for (final entry in entries) {
      if (cancelled()) break;
      if (entry.isDir || !entry.isMarkdown) continue;

      String content;
      try {
        final bytes = await readBytes(entry);
        content = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        continue; // an unreadable file doesn't fail the whole search
      }
      // Deliberately no isCancelled check here: the read already happened
      // (its cost is sunk), so this file's own matches are still processed
      // — only starting a *further* file is what cancellation should skip.
      // See the loop's own top-of-iteration check, and the one below.

      final lines = content.split('\n');
      for (var i = 0; i < lines.length && !capped; i++) {
        final line = lines[i];
        for (final m in matcher.allMatches(line)) {
          // Checked before adding, not after: this is what makes hitting
          // resultCap exactly (no further match anywhere) NOT count as
          // "capped" — only a match found *beyond* the cap does.
          if (matches.length >= resultCap) {
            capped = true;
            break;
          }
          final snippet = _snippet(line, m.start, m.end);
          matches.add(
            SearchMatch(
              entry: entry,
              line: i + 1,
              snippet: snippet.text,
              matchStart: snippet.start,
              matchEnd: snippet.end,
            ),
          );
          filesMatched.add('${entry.source.name}:${entry.relPath}');
        }
      }
      if (capped || cancelled()) break;

      // Chunking point — the brief's "stream/chunk across files (async,
      // cancellable on query change)". Yielding here (rather than only
      // once per whole search) is what lets a fast typist's second
      // keystroke actually cancel a scan already several files deep.
      await Future<void>.delayed(Duration.zero);
    }

    return SearchResult(
      matches: matches,
      fileCount: filesMatched.length,
      capped: capped,
    );
  }

  /// Flattens a vault tree (as `VaultState.entries`/`sampleEntries` hand
  /// back) into its Markdown-file leaves, depth-first — the shape [search]
  /// wants. Directories themselves never appear in the result.
  static List<VaultEntry> flattenMarkdownFiles(List<VaultEntry> roots) {
    final out = <VaultEntry>[];
    void walk(VaultEntry entry) {
      if (entry.isDir) {
        for (final child in entry.children) {
          walk(child);
        }
      } else if (entry.isMarkdown) {
        out.add(entry);
      }
    }

    for (final root in roots) {
      walk(root);
    }
    return out;
  }

  /// Builds the single [RegExp] every mode ultimately funnels through:
  /// [SearchFilters.regex] off means the query is escaped first
  /// ([RegExp.escape]) so it's matched as a literal substring;
  /// [SearchFilters.wholeWord] wraps whichever pattern resulted in
  /// non-capturing `\b` word-boundary anchors. Throws [FormatException] for
  /// an invalid regex query — [search] is the only caller, and it catches
  /// this.
  static RegExp _buildMatcher(String query, SearchFilters filters) {
    final pattern = filters.regex ? query : RegExp.escape(query);
    final wrapped = filters.wholeWord ? '\\b(?:$pattern)\\b' : pattern;
    return RegExp(wrapped, caseSensitive: filters.caseSensitive);
  }

  /// Windows [line] down to [snippetWindow] characters around
  /// `[start, end)` (the match), centering the match where the line has
  /// room on both sides and shifting the window toward whichever side has
  /// more content when it doesn't (a match near either edge of a long
  /// line). Returns the whole line, unchanged, when it's already no longer
  /// than [snippetWindow].
  static _Snippet _snippet(String line, int start, int end) {
    final matchLen = end - start;
    final radius = ((snippetWindow - matchLen) / 2).floor();
    final safeRadius = radius < 0 ? 0 : radius;

    var windowStart = start - safeRadius;
    var windowEnd = end + safeRadius;

    if (windowStart < 0) {
      windowEnd += -windowStart;
      windowStart = 0;
    }
    if (windowEnd > line.length) {
      windowStart -= windowEnd - line.length;
      windowEnd = line.length;
    }
    windowStart = windowStart.clamp(0, start);
    windowEnd = windowEnd.clamp(end, line.length);

    return _Snippet(
      text: line.substring(windowStart, windowEnd),
      start: start - windowStart,
      end: end - windowStart,
    );
  }
}

class _Snippet {
  const _Snippet({required this.text, required this.start, required this.end});

  final String text;
  final int start;
  final int end;
}
