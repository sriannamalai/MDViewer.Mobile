import 'package:flutter/material.dart';

import '../tokens.dart';
import '../widgets/tab_bar.dart';
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

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: IndexedStack(
        index: _current.index,
        children: const [
          _LibraryPlaceholder(),
          _SearchPlaceholder(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: AppTabBar(
        current: _current,
        onSelect: (tab) => setState(() => _current = tab),
      ),
    );
  }
}

/// Stand-in for the Library root — Task 4 replaces this with the real tree/
/// search-field/recents screen (design/README.md §01).
class _LibraryPlaceholder extends StatelessWidget {
  const _LibraryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(title: 'Library', note: 'Lands in Task 4.');
  }
}

/// Stand-in for the Search root — Task 7 replaces this with the real query/
/// filters/results screen (design/README.md §04).
class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(title: 'Search', note: 'Lands in Task 7.');
  }
}

class _TabPlaceholder extends StatelessWidget {
  const _TabPlaceholder({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: AppFonts.sourceSerif4,
                fontSize: AppTypeScale.h2Size,
                fontWeight: AppTypeScale.h2Weight,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              note,
              style: TextStyle(
                fontFamily: AppFonts.ibmPlexSans,
                fontSize: AppTypeScale.uiTextSize,
                color: tokens.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
