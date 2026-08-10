import 'package:flutter/material.dart';

import '../tokens.dart';

/// The Library screen's search field — design/README.md §01: "40px, radius
/// 10, `panel2` bg, 1px `line` border, placeholder 'Search files and
/// headings' 14px `text3`".
///
/// Non-editing by design: this is a navigation affordance, not a real text
/// field. Tapping it routes to the Search tab (per the task brief — real
/// query focus/keyboard behavior lands with Task 7's Search screen), so it
/// renders the placeholder copy as static text rather than hosting a
/// [TextField]/[FocusNode] that would invite typing here.
class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({super.key, required this.onTap});

  final VoidCallback onTap;

  static const String _placeholder = 'Search files and headings';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Material(
      color: tokens.panel2,
      borderRadius: BorderRadius.circular(AppGeometry.radiusSearchField),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppGeometry.radiusSearchField),
        child: Semantics(
          button: true,
          label: _placeholder,
          child: Container(
            height: AppGeometry.librarySearchFieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.line),
              borderRadius: BorderRadius.circular(
                AppGeometry.radiusSearchField,
              ),
            ),
            child: Row(
              children: [
                Text('⌕', style: TextStyle(fontSize: 14, color: tokens.text3)),
                const SizedBox(width: 8),
                // Expanded + ellipsis rather than a bare Text: on a narrow
                // viewport (small phones, or a split-screen width) the full
                // placeholder copy doesn't fit — it should truncate, not
                // overflow the row.
                Expanded(
                  child: Text(
                    _placeholder,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.ibmPlexSans,
                      fontSize: 14,
                      color: tokens.text3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
