import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation.dart';
import '../state/vault_state.dart';
import '../tokens.dart';
import '../vault/search.dart';

/// The Search screen — design/README.md §04: a query field (mono text,
/// accent caret, ✕ clear, `accentLine`-bordered while focused), three
/// filter-chip toggles (Aa case-sensitive / .* regex / Whole word), a count
/// line, and result cards (filename + `L<line>`, a mono snippet with the
/// match substring in `accent`). Tapping a result pushes the Reader
/// scrolled to the match line — the Reader's own load reads the document
/// and records it in Recents (mirroring Library's `_openFile`).
///
/// Searches every `.md` file across *both* vaults — the bundled Samples and
/// the picked folder (if any) — regardless of which one is "active";
/// design/README.md's state-management section lists `searchQuery` +
/// filters + results as vault-index-wide, not scoped to one section.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.autofocus = false});

  /// Requests keyboard focus once, right after this screen first builds —
  /// `AppShell` sets this true only when the user arrived via the Library
  /// search field's tap-through (not for a plain tab-bar switch to Search),
  /// by remounting this widget under a bumped key. See shell.dart's
  /// `_openSearchFromLibrary` doc comment for why a key bump (not a
  /// persisted flag) is the mechanism.
  final bool autofocus;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Duration _debounceDelay = Duration(milliseconds: 250);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  SearchFilters _filters = const SearchFilters();
  SearchResult? _result;
  Timer? _debounce;

  /// Bumped on every query/filter change; a running [VaultSearch.search]
  /// call's `isCancelled` closure reads this live, so a search already
  /// mid-scan when the user types again (or flips a chip) is abandoned
  /// rather than racing the newer one to `setState` — the brief's
  /// "cancellable on query change".
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _generation++;
    setState(() {}); // clear-button visibility / idle-vs-results switch
    _scheduleSearch();
  }

  void _setFilters(SearchFilters next) {
    _generation++;
    setState(() => _filters = next);
    // A chip toggle is a discrete, deliberate action (not a per-keystroke
    // event) — no debounce delay for it, unlike typing.
    _scheduleSearch(immediate: true);
  }

  void _clearQuery() {
    _controller.clear(); // fires _onQueryChanged via the listener
    _focusNode.requestFocus();
  }

  void _scheduleSearch({bool immediate = false}) {
    _debounce?.cancel();
    final generation = _generation;
    void run() => unawaited(_runSearch(generation));
    if (immediate) {
      run();
    } else {
      _debounce = Timer(_debounceDelay, run);
    }
  }

  Future<void> _runSearch(int generation) async {
    final query = _controller.text;
    if (query.isEmpty) {
      if (mounted && generation == _generation) {
        setState(() => _result = null);
      }
      return;
    }

    final vault = context.read<VaultState>();
    final entries = [
      ...VaultSearch.flattenMarkdownFiles(vault.sampleEntries),
      ...VaultSearch.flattenMarkdownFiles(vault.entries),
    ];

    final result = await VaultSearch.search(
      query: query,
      entries: entries,
      readBytes: vault.readRaw,
      filters: _filters,
      isCancelled: () => generation != _generation,
    );

    if (!mounted || generation != _generation) return;
    setState(() => _result = result);
  }

  /// Pushes the Reader for [match] — no pre-read here. `ReaderScreen._load`
  /// reads the document itself (recording it in Recents) and owns error
  /// surfacing; a pre-read would double every open over the platform
  /// channel and, if it threw, kill the tap handler unhandled before the
  /// Reader's error UI could show it.
  Future<void> _openResult(SearchMatch match) =>
      pushReader(context, match.entry, initialLine: match.line);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      // design/README.md §04: "OS keyboard sits below; results scroll
      // behind it" — the content doesn't reflow to avoid the keyboard.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SearchHeader(
              controller: _controller,
              focusNode: _focusNode,
              filters: _filters,
              onClear: _clearQuery,
              onFiltersChanged: _setFilters,
            ),
            Expanded(child: _buildBody(tokens)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppTokens tokens) {
    if (_controller.text.isEmpty) {
      return const _IdlePrompt();
    }

    final result = _result;
    if (result == null) {
      // Debounce window: a query was typed but the 250ms timer (or the
      // very first frame of the async search call) hasn't landed yet.
      return const SizedBox.shrink();
    }
    if (result.error != null) {
      return _InlineError(message: result.error!);
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CountLine(result: result),
          Expanded(
            child: result.matches.isEmpty
                ? const SizedBox.shrink() // the count line already reads "No results"
                : ListView.separated(
                    itemCount: result.matches.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppGeometry.searchCardGap),
                    itemBuilder: (context, index) => _ResultCard(
                      match: result.matches[index],
                      onTap: () => _openResult(result.matches[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The panel header: query field + filter chips, `panel` bg with a `line`
/// bottom border wrapping both rows (design/README.md §04's header block).
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.filters,
    required this.onClear,
    required this.onFiltersChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchFilters filters;
  final VoidCallback onClear;
  final ValueChanged<SearchFilters> onFiltersChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          children: [
            _QueryField(
              controller: controller,
              focusNode: focusNode,
              onClear: onClear,
            ),
            const SizedBox(height: 10),
            _FilterChips(filters: filters, onChanged: onFiltersChanged),
          ],
        ),
      ),
    );
  }
}

/// The 40px/radius-10 query field — `panel2` bg, `line` border by default,
/// `accentLine` while focused (design/README.md §04), mono query text with
/// an `accent` cursor, and a ✕ clear button shown only once there's text to
/// clear.
class _QueryField extends StatelessWidget {
  const _QueryField({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  static const String _placeholder = 'Search files and headings';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, controller]),
      builder: (context, _) {
        final borderColor = focusNode.hasFocus
            ? tokens.accentLine
            : tokens.line;
        return Container(
          height: AppGeometry.librarySearchFieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(AppGeometry.radiusSearchField),
          ),
          child: Row(
            children: [
              Text(
                '⌕',
                style: TextStyle(
                  fontSize: AppTypeScale.searchIconSize,
                  color: tokens.text3,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: false,
                  cursorColor: tokens.accent,
                  cursorWidth: 1.5,
                  style: TextStyle(
                    fontFamily: AppFonts.jetBrainsMono,
                    fontSize: AppTypeScale.searchQueryTextSize,
                    color: tokens.text,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: _placeholder,
                    hintStyle: TextStyle(
                      fontFamily: AppFonts.jetBrainsMono,
                      fontSize: AppTypeScale.searchQueryTextSize,
                      color: tokens.text3,
                    ),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '✕',
                      style: TextStyle(
                        fontSize: AppTypeScale.searchClearGlyphSize,
                        color: tokens.text3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The Aa / .* / Whole word toggle chips — 20px-radius pills, `accentSoft`+
/// `accent` when active, a 1px `line` border + `text3` when not (design/
/// README.md §04).
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.filters, required this.onChanged});

  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label: 'Aa',
          active: filters.caseSensitive,
          onTap: () => onChanged(
            filters.copyWith(caseSensitive: !filters.caseSensitive),
          ),
        ),
        const SizedBox(width: AppGeometry.searchChipGap),
        _Chip(
          label: '.*',
          active: filters.regex,
          onTap: () => onChanged(filters.copyWith(regex: !filters.regex)),
        ),
        const SizedBox(width: AppGeometry.searchChipGap),
        _Chip(
          label: 'Whole word',
          active: filters.wholeWord,
          onTap: () =>
              onChanged(filters.copyWith(wholeWord: !filters.wholeWord)),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Material(
      color: active ? tokens.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppGeometry.pillRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppGeometry.pillRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppGeometry.searchChipPaddingH,
            vertical: AppGeometry.searchChipPaddingV,
          ),
          decoration: BoxDecoration(
            border: active ? null : Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(AppGeometry.pillRadius),
          ),
          child: Semantics(
            button: true,
            toggled: active,
            label: label,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.ibmPlexSans,
                fontSize: AppTypeScale.searchChipTextSize,
                fontWeight: active
                    ? AppTypeScale.searchChipActiveWeight
                    : FontWeight.w400,
                color: active ? tokens.accent : tokens.text3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The idle state before any query has been typed — design/README.md §04
/// has no spec for this (its mockup always shows an active search), so this
/// is a minimal tokens-styled placeholder, the same "no spec → minimal
/// tokens-styled placeholder, documented" convention the Outline sheet's
/// `_EmptyState` already established for its own no-headings case.
class _IdlePrompt extends StatelessWidget {
  const _IdlePrompt();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Search across your vault by filename or heading text.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.ibmPlexSans,
            fontSize: AppTypeScale.uiTextSize,
            color: tokens.text3,
          ),
        ),
      ),
    );
  }
}

/// The inline "invalid regex" state — design/README.md §04 says errors show
/// inline, never a thrown exception (`vault/search.dart`'s
/// `SearchResult.error`); no design spec covers its exact look, so this
/// reuses the accent color the rest of the app treats as its one
/// warm/attention hue (see tokens.dart's `AppTheme._build` doc comment on
/// `error`/`accent`).
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Invalid pattern: $message',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.jetBrainsMono,
            fontSize: AppTypeScale.uiTextSize,
            color: tokens.accent,
          ),
        ),
      ),
    );
  }
}

/// "N results in M files", with a "(showing first `resultCap`)" suffix once
/// [SearchResult.capped] — design/README.md §04's count line (11px `text3`).
class _CountLine extends StatelessWidget {
  const _CountLine({required this.result});

  final SearchResult result;

  static String _format(SearchResult result) {
    if (result.matches.isEmpty) return 'No results';
    final resultsWord = result.matches.length == 1 ? 'result' : 'results';
    final filesWord = result.fileCount == 1 ? 'file' : 'files';
    final plus = result.capped ? '+' : '';
    final base =
        '${result.matches.length}$plus $resultsWord in ${result.fileCount} $filesWord';
    return result.capped
        ? '$base (showing first ${VaultSearch.resultCap})'
        : base;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Text(
        _format(result),
        style: TextStyle(
          fontFamily: AppFonts.ibmPlexSans,
          fontSize: AppTypeScale.searchCountLineSize,
          color: tokens.text3,
        ),
      ),
    );
  }
}

/// One result card — design/README.md §04: radius 10, padding 10×12,
/// filename (12px/500) + `L<line>` (mono, `text3`) on the top row, a mono
/// 11.5px snippet below with the match substring in `accent`. Pressed
/// feedback uses `accentSoft` (the design's documented hover-fill stand-in
/// for touch — README §Interactions: "pressed states use the hover fills
/// from TOKENS (`panel2`/`accentSoft`)"); there's no persistent "selected"
/// concept on a touch result list, unlike the static mockup's one
/// permanently-highlighted example card.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.match, required this.onTap});

  final SearchMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppGeometry.radiusSearchCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppGeometry.radiusSearchCard),
        highlightColor: tokens.accentSoft,
        splashColor: tokens.accentSoft,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppGeometry.searchCardPaddingH,
            vertical: AppGeometry.searchCardPaddingV,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      match.entry.relPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.ibmPlexSans,
                        fontSize: AppTypeScale.searchCardMetaSize,
                        fontWeight: AppTypeScale.searchCardFilenameWeight,
                        color: tokens.text,
                      ),
                    ),
                  ),
                  Text(
                    'L${match.line}',
                    style: TextStyle(
                      fontFamily: AppFonts.jetBrainsMono,
                      fontSize: AppTypeScale.searchCardMetaSize,
                      color: tokens.text3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: _highlightedSpans(tokens)),
                style: TextStyle(
                  fontFamily: AppFonts.jetBrainsMono,
                  fontSize: AppTypeScale.searchSnippetSize,
                  height: AppTypeScale.searchSnippetLineHeight,
                  color: tokens.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TextSpan> _highlightedSpans(AppTokens tokens) {
    final text = match.snippet;
    final start = match.matchStart.clamp(0, text.length);
    final end = match.matchEnd.clamp(start, text.length);
    final matchStyle = TextStyle(color: tokens.accent);

    return [
      if (start > 0) TextSpan(text: text.substring(0, start)),
      if (end > start)
        TextSpan(text: text.substring(start, end), style: matchStyle),
      if (end < text.length) TextSpan(text: text.substring(end)),
    ];
  }
}
