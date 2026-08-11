import 'package:flutter/material.dart';

import '../tokens.dart';
import '../vault/vault_entry.dart';

/// Renders one [VaultEntry] (folder or file) and, when a folder is
/// expanded, its children — design/README.md §01's tree spec: 48px rows,
/// radius 10, disclosure caret + folder glyph + name for directories; mono
/// "M" badge + name + chevron for files. Folders-first-alphabetical
/// ordering already comes out of `VaultIndex.build`; this widget only lays
/// out whatever order [entry.children] is in.
///
/// [depth] is the folder-nesting depth ([entry] itself is a *direct* child
/// of a folder at `depth - 1`; top-level tree roots pass `depth: 0`) — it
/// drives the indent math in [VaultFolderRow]/[LibraryFileRow].
class VaultTreeRow extends StatelessWidget {
  const VaultTreeRow({
    super.key,
    required this.entry,
    required this.depth,
    required this.isExpanded,
    required this.onToggle,
    required this.onTapFile,
    required this.isActive,
  });

  final VaultEntry entry;
  final int depth;
  final bool Function(VaultEntry entry) isExpanded;
  final void Function(VaultEntry entry) onToggle;
  final void Function(VaultEntry entry) onTapFile;
  final bool Function(VaultEntry entry) isActive;

  @override
  Widget build(BuildContext context) {
    if (!entry.isDir) {
      return LibraryFileRow(
        entry: entry,
        depth: depth,
        active: isActive(entry),
        onTap: () => onTapFile(entry),
      );
    }

    final expanded = isExpanded(entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VaultFolderRow(
          entry: entry,
          depth: depth,
          expanded: expanded,
          onTap: () => onToggle(entry),
        ),
        if (expanded)
          for (final child in entry.children)
            VaultTreeRow(
              entry: child,
              depth: depth + 1,
              isExpanded: isExpanded,
              onToggle: onToggle,
              onTapFile: onTapFile,
              isActive: isActive,
            ),
      ],
    );
  }
}

/// One folder row: disclosure caret (rotates ▸→▾), folder glyph, name, and
/// a right-aligned mono child-count meta (design's "child count or ›" —
/// folders always show the count).
class VaultFolderRow extends StatelessWidget {
  const VaultFolderRow({
    super.key,
    required this.entry,
    required this.depth,
    required this.expanded,
    required this.onTap,
  });

  final VaultEntry entry;
  final int depth;
  final bool expanded;
  final VoidCallback onTap;

  // Only one nested-folder example exists in the design reference (top
  // level, depth 0, padding-left 8px) — deeper levels extrapolate an 8px
  // step per level, mirroring the row-content indent unit used elsewhere
  // in the tree (see LibraryFileRow._paddingLeft's doc comment).
  static double _paddingLeft(int depth) => 8 + 8.0 * depth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppGeometry.radiusLibraryRow),
        highlightColor: tokens.panel2,
        splashColor: tokens.panel2,
        child: Container(
          height: AppGeometry.rowHeightMax,
          padding: EdgeInsets.only(left: _paddingLeft(depth), right: 8),
          child: Row(
            children: [
              SizedBox(
                width: 10,
                child: Text(
                  expanded ? '▾' : '▸',
                  style: TextStyle(
                    fontSize: AppTypeScale.libraryTreeCaretSize,
                    color: tokens.text3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Opacity(
                opacity: 0.75,
                child: Text(
                  '📁',
                  style: TextStyle(
                    fontSize: AppTypeScale.libraryFolderGlyphSize,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.ibmPlexSans,
                    fontSize: AppTypeScale.libraryRowTextSize,
                    color: tokens.text,
                  ),
                ),
              ),
              Text(
                '${entry.mdCount}',
                style: TextStyle(
                  fontFamily: AppFonts.jetBrainsMono,
                  fontSize: AppTypeScale.libraryRowMetaSize,
                  color: tokens.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One Markdown-file row: mono "M" badge, name, and a right-aligned
/// [trailing] widget (the "›" chevron for tree rows, a relative-time mono
/// string for Recent rows — design/README.md §01's row spec covers both:
/// "right-aligned meta (child count or ›)" for the tree, "'Recent' section:
/// same rows with relative-time meta" for recents).
///
/// [active] fills the row `accentSoft` and colors the name/badge-adjacent
/// chevron `accent`/500, per "Active file: `accentSoft` fill, `accent`
/// text/500".
class LibraryFileRow extends StatelessWidget {
  const LibraryFileRow({
    super.key,
    required this.entry,
    required this.depth,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  final VaultEntry entry;
  final int depth;
  final bool active;
  final VoidCallback onTap;

  /// Defaults to the "›" chevron (the tree's own file-row meta) when null —
  /// Recent rows override this with a relative-time label instead.
  final Widget? trailing;

  // The HTML reference (design/reference/MarkdownViewerMobile.dc.html,
  // screen-01) renders a file row's badge at the same absolute x=30px via
  // two different techniques depending on markup: a nested file under an
  // expanded folder uses `padding:0 8px 0 30px` (left padding 30); a
  // top-level "loose" file (a sibling of the folders, not nested under any
  // of them) uses base `padding:0 8px` plus an inline `margin-left:22px` on
  // the badge itself (8 + 22 = 30, the same total). Both examples land at
  // 30px regardless of true tree depth, so depth 0 (loose root file) and
  // depth 1 (direct child of a depth-0 folder) both resolve to the same
  // 30px indent here; only a *second* level of folder nesting (depth >= 2,
  // no example in the reference) adds a further 8px per level.
  static double _paddingLeft(int depth) => 30 + 8 * (depth > 1 ? depth - 1 : 0);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final nameColor = active ? tokens.accent : tokens.text;
    // The reference markup's inactive chevron (`#c8c4bc`) isn't a TOKENS.md
    // color; `text3` is the closest palette token and is what every other
    // tertiary/meta glyph in this screen uses, so the chevron follows suit
    // rather than introducing an undocumented literal.
    final chevronColor = active ? tokens.accent : tokens.text3;

    return Material(
      color: active ? tokens.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppGeometry.radiusLibraryRow),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppGeometry.radiusLibraryRow),
        highlightColor: tokens.panel2,
        splashColor: tokens.panel2,
        child: Container(
          height: AppGeometry.rowHeightMax,
          padding: EdgeInsets.only(left: _paddingLeft(depth), right: 8),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(
                  'M',
                  style: TextStyle(
                    fontFamily: AppFonts.jetBrainsMono,
                    fontSize: AppTypeScale.libraryBadgeSize,
                    color: tokens.accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.ibmPlexSans,
                    fontSize: AppTypeScale.libraryRowTextSize,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                    color: nameColor,
                  ),
                ),
              ),
              trailing ??
                  Text(
                    '›',
                    style: TextStyle(
                      fontSize: AppTypeScale.libraryChevronSize,
                      color: chevronColor,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
