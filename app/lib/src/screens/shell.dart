import 'package:flutter/material.dart';

import '../tokens.dart';
import '../widgets/tab_bar.dart';
import 'library.dart';
import 'search.dart';
import 'settings.dart';

/// The app shell: three tab roots (Library, Search, Settings) behind
/// [AppTabBar], per design/README.md §Interactions ("Tabs switch root
/// screens"). Reader is pushed above this whole shell via
/// `navigation.dart`'s `pushReader`, not hosted as a fourth tab.
///
/// Tab bodies live in an [IndexedStack] rather than being rebuilt on
/// selection, so switching tabs preserves each root's scroll position/
/// widget state (design's Library search field focus, Settings' stepper,
/// etc.) instead of resetting it every time.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _current = AppTab.library;

  /// Bumped only by [_openSearchFromLibrary] (never by a plain tab-bar tap
  /// on Search) and used as [SearchScreen]'s `key` — the mechanism behind
  /// "the query field autofocuses when arriving via the Library search
  /// field's tap, but not on every manual visit to the Search tab" (task-7
  /// brief). Changing a widget's key forces Flutter to discard its old
  /// [State] and build a fresh one (fresh empty query, `autofocus: true`)
  /// even though it stays at the same [IndexedStack] index; a plain
  /// tab-bar switch leaves the key alone, so [SearchScreen]'s existing
  /// state (typed query, results, filters) survives exactly like every
  /// other tab's does.
  int _searchAutofocusToken = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: IndexedStack(
        index: _current.index,
        children: [
          LibraryScreen(onOpenSearch: _openSearchFromLibrary),
          SearchScreen(
            key: ValueKey(_searchAutofocusToken),
            autofocus: _searchAutofocusToken > 0,
          ),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: AppTabBar(current: _current, onSelect: _switchTo),
    );
  }

  void _switchTo(AppTab tab) => setState(() => _current = tab);

  void _openSearchFromLibrary() {
    setState(() {
      _searchAutofocusToken++;
      _current = AppTab.search;
    });
  }
}
