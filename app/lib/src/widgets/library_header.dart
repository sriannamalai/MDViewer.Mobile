import 'package:flutter/material.dart';

import '../tokens.dart';
import 'app_icon_tile.dart';
import 'theme_toggle_button.dart';

/// The Library screen's header row: icon tile + two-tone wordmark, right
/// aligned [ThemeToggleButton] — design/README.md §01: "26px app icon tile
/// ... + wordmark 17px/600 (\"MarkDown\" `text`, \"Viewer\" `text3`/500),
/// right 34px circular theme toggle". The surrounding panel surface / bottom
/// border / padding belong to the screen (they also frame the search field
/// below this row), not this widget.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Row(
      children: [
        const AppIconTile(size: AppGeometry.libraryHeaderIconTileSize),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: AppFonts.ibmPlexSans,
              fontSize: AppTypeScale.libraryWordmarkSize,
              fontWeight: AppTypeScale.libraryWordmarkWeight,
              letterSpacing: AppTypeScale.libraryWordmarkLetterSpacing,
            ),
            children: [
              TextSpan(
                text: 'MarkDown',
                style: TextStyle(color: tokens.text),
              ),
              TextSpan(
                text: 'Viewer',
                style: TextStyle(
                  color: tokens.text3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        const ThemeToggleButton(),
      ],
    );
  }
}
