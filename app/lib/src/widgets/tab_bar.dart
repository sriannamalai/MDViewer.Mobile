import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens.dart';

/// One of the three tab-bar destinations, in display order — design/
/// README.md §01: "Library / Search / Settings".
enum AppTab { library, search, settings }

class _TabSpec {
  const _TabSpec(this.glyph, this.label);
  final String glyph;
  final String label;
}

// Glyphs transcribed verbatim from the design reference's tab bar markup
// (design/reference/MarkdownViewerMobile.dc.html, screen-01's bottom bar):
// "▤" Library, "⌕" Search, "⚙" Settings.
const Map<AppTab, _TabSpec> _tabSpecs = {
  AppTab.library: _TabSpec('▤', 'Library'),
  AppTab.search: _TabSpec('⌕', 'Search'),
  AppTab.settings: _TabSpec('⚙', 'Settings'),
};

/// The bottom tab bar, built from tokens rather than Material's
/// `BottomNavigationBar` (whose default visuals don't match the design):
/// blurred `panel` surface at .92 opacity, 1px `line` top border, three
/// equal-width items (19px icon glyph + 10.5px label), active `accent` /
/// inactive `text3`. 88px total height "incl. home-indicator clearance" per
/// design/README.md §01 — reproduced here as a fixed content zone plus
/// `MediaQuery` bottom padding (the real device's safe-area inset) rather
/// than a hardcoded clearance, so it holds up across devices.
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppGeometry.barBlurSigma,
          sigmaY: AppGeometry.barBlurSigma,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.panel.withValues(
              alpha: AppGeometry.barSurfaceOpacityMax,
            ),
            border: Border(top: BorderSide(color: tokens.line, width: 1)),
          ),
          // No fixed total height: the content zone (icon + gap + label,
          // padded top/bottom) sizes itself to its own intrinsic height —
          // avoids a RenderFlex overflow on hosts whose font metrics run
          // taller than the design reference's (e.g. `flutter test`'s
          // default text rendering). `bottomInset` — the real device's
          // home-indicator clearance — is added on top of an 8px breathing
          // pad, reproducing design/README.md §01's "88px incl.
          // home-indicator clearance" without hardcoding one device's inset.
          padding: EdgeInsets.only(
            top: 8,
            bottom: (bottomInset > 0 ? bottomInset : 0) + 8,
          ),
          child: Row(
            children: AppTab.values.map((tab) {
              final spec = _tabSpecs[tab]!;
              final active = tab == current;
              final color = active ? tokens.accent : tokens.text3;
              return Expanded(
                child: InkResponse(
                  key: ValueKey('appTab-${tab.name}'),
                  onTap: () => onSelect(tab),
                  containedInkWell: true,
                  highlightShape: BoxShape.rectangle,
                  child: Semantics(
                    button: true,
                    selected: active,
                    label: spec.label,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          spec.glyph,
                          style: TextStyle(
                            fontSize: AppTypeScale.tabGlyphSize,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          spec.label,
                          style: TextStyle(
                            fontFamily: AppFonts.ibmPlexSans,
                            fontSize: AppTypeScale.uiLabelSize,
                            fontWeight: active
                                ? AppTypeScale.tabLabelActiveWeight
                                : AppTypeScale.uiTextWeightMin,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
