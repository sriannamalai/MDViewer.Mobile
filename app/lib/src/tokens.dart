// Design tokens transcribed verbatim from design/TOKENS.md (color tables,
// both themes) and design/README.md (§Fidelity + per-screen type sizes for
// the mobile scale). This is the ONLY place `Color(...)` literals for the
// app's palette may appear — every other file reaches colors through
// `AppTokens.of(context)` or the ambient `Theme.of(context).colorScheme`
// derived from it. Reviewers: grep for ad-hoc `Color(0x` outside this file.
//
// Source of truth:
//   - design/TOKENS.md            → color tables (light + dark), spacing/geometry
//   - design/README.md §Fidelity  → mobile type-scale deltas (body/H1/H2/code)
//   - design/README.md §Screens   → per-role sizes used verbatim below
import 'package:flutter/material.dart';

/// Font family names registered in pubspec.yaml. Later tasks must reference
/// these constants rather than repeating the string literals.
class AppFonts {
  AppFonts._();

  static const String ibmPlexSans = 'IBMPlexSans';
  static const String sourceSerif4 = 'SourceSerif4';
  static const String jetBrainsMono = 'JetBrainsMono';
}

/// Mobile type scale, per design/README.md §Fidelity ("Prose type is
/// slightly larger than desktop for arm's-length reading: body 15px/1.68,
/// H1 27px, H2 19px, code 12px") and the per-screen numbers under §Screens
/// (Reader). Sizes not called out with a mobile-specific delta (H3, UI
/// chrome text/labels/meta) carry the desktop TOKENS.md values unchanged —
/// TOKENS.md's Typography table is the source for those.
class AppTypeScale {
  AppTypeScale._();

  // Prose — mobile deltas from README §Fidelity / §Screens (Reader).
  static const double bodySize = 15;
  static const double bodyLineHeight = 1.68; // multiplier
  static const FontWeight bodyWeight = FontWeight.w400;

  static const double h1Size = 27;
  static const FontWeight h1Weight = FontWeight.w700;
  static const double h1LetterSpacing = -0.02 * h1Size; // ls -.02em
  static const double h1LineHeight = 1.15;

  static const double h2Size = 19;
  static const FontWeight h2Weight = FontWeight.w600;
  static const double h2LetterSpacing = -0.01 * h2Size; // ls -.01em
  static const double h2BorderBottomWidth = 1; // `line`, per TOKENS.md
  static const double h2PaddingBottom = 7;
  static const double h2MarginTop = 42;
  static const double h2MarginBottom = 12;

  static const double codeSize = 12;
  static const double codeLineHeight = 1.65; // multiplier, desktop-unchanged

  // Not given a mobile-specific delta — desktop TOKENS.md value carried
  // through verbatim.
  static const double h3Size = 17;
  static const FontWeight h3Weight = FontWeight.w600;
  static const double h3MarginTop = 28;
  static const double h3MarginBottom = 8;

  // UI chrome (tabs, sidebar/tab-bar labels, buttons) — unchanged from
  // desktop TOKENS.md; mobile has no override in README §Fidelity.
  static const double uiTextSize = 12.5;
  static const FontWeight uiTextWeightMin = FontWeight.w400;
  static const FontWeight uiTextWeightMax = FontWeight.w600;

  static const double uiLabelSize = 10.5;
  static const FontWeight uiLabelWeight = FontWeight.w600;
  static const double uiLabelLetterSpacing = 0.09 * uiLabelSize; // ls .09em

  static const double uiMetaSizeMin = 10.5;
  static const double uiMetaSizeMax = 11.5;
  static const FontWeight uiMetaWeightMin = FontWeight.w400;
  static const FontWeight uiMetaWeightMax = FontWeight.w500;

  // §01 Library — the section label and header wordmark carry
  // mobile-specific sizes distinct from the desktop UI-label token
  // (uiLabelSize 10.5). Transcribed from design/README.md §01 ("uppercase
  // section label (11px/600/.09em text3)") and confirmed verbatim against
  // design/reference/MarkdownViewerMobile.dc.html's screen-01 markup
  // (`font-size:11px` on the section-label divs; `font-size:17px;
  // font-weight:600; letter-spacing:-.2px` on the wordmark span).
  static const double librarySectionLabelSize = 11;
  static const FontWeight librarySectionLabelWeight = FontWeight.w600;
  static const double librarySectionLabelLetterSpacing =
      0.09 * librarySectionLabelSize;

  static const double libraryWordmarkSize = 17;
  static const FontWeight libraryWordmarkWeight = FontWeight.w600;
  static const double libraryWordmarkLetterSpacing = -0.2;

  // §02 Reader — header/bottom-bar sizes not covered by any desktop-shared
  // token. Transcribed from design/README.md §02 ("filename 14px/600 ...
  // 40px circular 'Aa'") and confirmed against the HTML reference's
  // screen-02 markup (`font-size:20px` on the back-button glyph,
  // `font-size:15px` on the share glyph, `font-size:13px; font-weight:500`
  // on the Outline pill's glyph+label, `font-size:11px` on the "section ·
  // %" line, `font-size:14px` on the Aa glyph). The header's "vault · read
  // time" mono line reuses the desktop-shared `uiMetaSizeMin` (10.5px) —
  // README explicitly calls it "mono 10.5px text3", the same value.
  static const double readerBackGlyphSize = 20;
  static const double readerShareGlyphSize = 15;
  static const double readerFilenameSize = 14;
  static const FontWeight readerFilenameWeight = FontWeight.w600;
  static const double readerOutlineGlyphSize = 13;
  static const double readerOutlineTextSize = 13;
  static const FontWeight readerOutlineTextWeight = FontWeight.w500;
  static const double readerSectionSize = 11;
  static const double readerAaGlyphSize = 14;

  // §03 Outline sheet — transcribed from design/README.md §03 ("header row
  // — uppercase 'On this page' label left, '1,140 words · 5 min' mono 11px
  // text3 right"; "Outline rows: 44px, radius 10, 15px text; H1 500 text2,
  // H2 indent 28px, H3 indent 42px text3") and confirmed against the HTML
  // reference's screen-03 markup (`font-size:11px; font-weight:600;
  // letter-spacing:.09em` on the label, `font-size:11px` mono on the meta,
  // `font-size:15px` on every row, no explicit `font-weight` on inactive H2/
  // H3 rows (browser default 400), `font-weight:600` on the active row).
  static const double outlineHeaderLabelSize = 11;
  static const FontWeight outlineHeaderLabelWeight = FontWeight.w600;
  static const double outlineHeaderLabelLetterSpacing =
      0.09 * outlineHeaderLabelSize;
  static const double outlineHeaderMetaSize = 11;

  static const double outlineRowTextSize = 15;
  static const FontWeight outlineRowH1Weight = FontWeight.w500;
  static const FontWeight outlineRowInactiveWeight = FontWeight.w400;
  static const FontWeight outlineRowActiveWeight = FontWeight.w600;

  // §04 Search — transcribed from design/README.md §04 ("mono query text +
  // accent caret, ✕ clear"; "filter chips ... 20px-radius pills"; "count
  // line 11px text3"; "cards ... filename 12px/500 + L<line> mono right;
  // snippet mono 11.5px text2 with match substring in accent") and confirmed
  // against the HTML reference's screen-04 markup: the query row's `⌕`/text/
  // `✕` all share `font-size:14px` (bumped the magnifier from Library's 14px
  // — same value, kept a distinct name since it's a different screen's
  // token per the file's own precedent); chips `font-size:11px;
  // padding:4px 10px`; the count line `font-size:11px`; a result card's
  // filename row `font-size:12px` (both the filename span and the `L<line>`
  // span — the HTML never overrides size on the second span, so they share
  // one token); the snippet div `font-size:11.5px; line-height:1.55`.
  static const double searchQueryTextSize = 14;
  static const double searchIconSize = 14;
  static const double searchClearGlyphSize = 13;
  static const double searchChipTextSize = 11;
  static const FontWeight searchChipActiveWeight = FontWeight.w500;
  static const double searchCountLineSize = 11;
  static const double searchCardMetaSize = 12; // filename + "L<line>"
  static const FontWeight searchCardFilenameWeight = FontWeight.w500;
  static const double searchSnippetSize = 11.5;
  static const double searchSnippetLineHeight = 1.55; // multiplier
}

/// Spacing & geometry constants from TOKENS.md's "Spacing & geometry"
/// section, plus the mobile deltas README §Design tokens calls out
/// ("row height 44–48px · sheet radius 18 · pill controls radius 20 · bar
/// blur `blur(12px)` at .92–.94 surface opacity").
class AppGeometry {
  AppGeometry._();

  // Radii (TOKENS.md).
  static const double radiusWindow = 12;
  static const double radiusOverlay = 12;
  static const double radiusBlock = 8; // code blocks/tables/callouts
  static const double radiusButtonMin = 6;
  static const double radiusButtonMax = 8;
  static const double radiusSearchPill = 7;
  static const double radiusBadgeMin = 4;
  static const double radiusBadgeMax = 5;

  // Mobile-specific deltas (README §Design tokens).
  static const double rowHeightMin = 44;
  static const double rowHeightMax = 48;
  static const double sheetRadius = 18;
  static const double pillRadius = 20;
  static const double barBlurSigma = 12;
  static const double barSurfaceOpacityMin = 0.92;
  static const double barSurfaceOpacityMax = 0.94;

  // Motion (TOKENS.md).
  static const Duration motionPanel = Duration(milliseconds: 220);
  static const Curve motionPanelCurve = Cubic(0.2, 0.7, 0.3, 1);
  static const Duration motionOverlay = Duration(milliseconds: 160);
  static const Duration motionVeil = Duration(milliseconds: 140);

  static const double minTapTarget = 44; // README "All tap targets >=44px"

  // §01 Library — row/search-field radius (10px) and the header icon tile
  // size, distinct from the desktop button/block radii (6-8px) already
  // above. Transcribed from the HTML reference's screen-01 markup
  // (`border-radius:10px` on both the search field and tree rows;
  // `width:26px; height:26px` on the icon tile).
  static const double radiusLibraryRow = 10;
  static const double radiusSearchField = 10;
  static const double librarySearchFieldHeight = 40;
  static const double libraryHeaderIconTileSize = 26;

  // §03 Outline sheet — transcribed from the HTML reference's screen-03
  // markup (design/reference/MarkdownViewerMobile.dc.html): the sheet's own
  // padding is `10px 8px 40px` (top/horizontal/bottom); the header row adds
  // a further `0 14px 10px` on top of that (`outlineHeaderHorizontalPadding`
  // / `outlineHeaderBottomPadding`); the rows wrapper adds a further `0 6px`
  // (`outlineRowsHorizontalPadding`); each row then adds its own indent —
  // `0 14px` for H1, `0 14px 0 28px` for H2, `0 14px 0 42px` for H3 — so a
  // row's *effective* left indent from the screen edge is
  // `outlineSheetHorizontalPadding + outlineRowsHorizontalPadding +` the
  // level's own [outlineIndentH1]/[outlineIndentH2]/[outlineIndentH3].
  // Radius/row-height reuse the shared [radiusButtonMin]-style pattern of a
  // screen-specific name even where the value coincides with another
  // screen's token (see [radiusLibraryRow]/[radiusSearchField], both 10).
  static const double sheetTopPadding = 10;
  static const double outlineSheetHorizontalPadding = 8;
  static const double outlineSheetBottomPaddingMin = 40;
  static const double outlineHeaderHorizontalPadding = 14;
  static const double outlineHeaderBottomPadding = 10;
  static const double outlineRowsHorizontalPadding = 6;
  static const double radiusOutlineRow = 10;
  static const double outlineIndentH1 = 14;
  static const double outlineIndentH2 = 28;
  static const double outlineIndentH3 = 42;
  static const double outlineRowPaddingRight = 14;
  static const double outlineGrabberWidth = 40;
  static const double outlineGrabberHeight = 4;
  static const double outlineGrabberRadius = 2;
  static const double outlineGrabberBottomMargin = 12;

  // The outline sheet's drop shadow — design/README.md §03: "shadow
  // `0 -12px 40px rgba(0,0,0,.18)`" (CSS box-shadow order: x-offset,
  // y-offset, blur-radius; color lives in [AppOverlay.outlineSheetShadow]
  // since it's a `Color(...)` literal). Flutter's [Offset] uses the same
  // sign convention as CSS — negative `dy` shifts the shadow upward.
  static const double outlineSheetShadowOffsetY = -12;
  static const double outlineSheetShadowBlurRadius = 40;

  // The outline sheet's entrance animation — design/README.md §Interactions
  // ("Outline opens the sheet (spring, ~0.3s)"). Reuses [motionPanelCurve]
  // (TOKENS.md's only spring-shaped easing curve) rather than inventing a
  // second one; only the duration is outline-specific.
  static const Duration outlineSheetDuration = Duration(milliseconds: 300);

  // §04 Search — transcribed from the HTML reference's screen-04 markup:
  // chip pills reuse [pillRadius] (also 20 there, same precedent as
  // [radiusOutlineRow] reusing [radiusLibraryRow]'s value under a
  // screen-specific name); chip padding `4px 10px`; the chips row's own gap
  // `6px`; a result card's radius `10px` and padding `10px 12px`; the gap
  // between cards `4px` (the results column's `gap:4px`).
  static const double searchChipPaddingH = 10;
  static const double searchChipPaddingV = 4;
  static const double searchChipGap = 6;
  static const double radiusSearchCard = 10;
  static const double searchCardPaddingH = 12;
  static const double searchCardPaddingV = 10;
  static const double searchCardGap = 4;
}

/// Non-themed overlay colors — identical across light/dark (unlike
/// [AppTokens]'s per-theme palette), so they don't belong in either color
/// table. Currently just the Outline sheet's veil (design/README.md §03:
/// "Veil `rgba(10,11,12,.28)`"; the same value in the HTML reference's
/// screen-03 markup regardless of theme). Kept in tokens.dart alongside
/// [AppTokens] so it stays the only file with `Color(...)` literals.
class AppOverlay {
  AppOverlay._();

  static const Color outlineVeil = Color(0x470A0B0C); // rgba(10,11,12,.28)

  /// The Outline sheet's drop shadow — design/README.md §03: "shadow
  /// `0 -12px 40px rgba(0,0,0,.18)`". Paired with
  /// [AppGeometry.outlineSheetShadowOffsetY]/[outlineSheetShadowBlurRadius].
  static const Color outlineSheetShadow = Color(0x2E000000); // rgba(0,0,0,.18)
}

/// Color tokens for one theme (light or dark), transcribed 1:1 from
/// TOKENS.md's two color tables. Field names match the token names in
/// TOKENS.md exactly.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.line2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentSoft,
    required this.accentLine,
    required this.code,
    required this.ok,
    required this.note,
    required this.noteSoft,
    required this.syntaxKw,
    required this.syntaxStr,
    required this.syntaxCom,
    required this.syntaxFn,
    required this.syntaxNum,
  });

  final Color bg;
  final Color panel;
  final Color panel2;
  final Color line;
  final Color line2;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentSoft;
  final Color accentLine;
  final Color code;
  final Color ok;
  final Color note;
  final Color noteSoft;

  // Code highlighting: keyword / string / comment / function / number.
  final Color syntaxKw;
  final Color syntaxStr;
  final Color syntaxCom;
  final Color syntaxFn;
  final Color syntaxNum;

  /// TOKENS.md — Color · light theme.
  static const AppTokens light = AppTokens(
    bg: Color(0xFFF7F6F3),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFF1EFEB),
    line: Color(0xFFE3DFD8),
    line2: Color(0xFFEEEBE5),
    text: Color(0xFF1B1B1E),
    text2: Color(0xFF6C6960),
    text3: Color(0xFF96928A),
    accent: Color(0xFFC1502E),
    accentSoft: Color(0x1AC1502E), // rgba(193,80,46,.10)
    accentLine: Color(0x59C1502E), // rgba(193,80,46,.35)
    code: Color(0xFFF4F2EE),
    ok: Color(0xFF2F7A4F),
    note: Color(0xFF2F6BBF),
    noteSoft: Color(0x172F6BBF), // rgba(47,107,191,.09)
    syntaxKw: Color(0xFF9B2C6F),
    syntaxStr: Color(0xFF2F7A4F),
    syntaxCom: Color(0xFF9A958C),
    syntaxFn: Color(0xFF2F6BBF),
    syntaxNum: Color(0xFFA35A09),
  );

  /// TOKENS.md — Color · dark theme.
  static const AppTokens dark = AppTokens(
    bg: Color(0xFF131418),
    panel: Color(0xFF1A1C21),
    panel2: Color(0xFF212429),
    line: Color(0xFF2C3037),
    line2: Color(0xFF23262B),
    text: Color(0xFFE9E7E2),
    text2: Color(0xFF9B988F),
    text3: Color(0xFF75726B),
    accent: Color(0xFFE97A52),
    accentSoft: Color(0x21E97A52), // rgba(233,122,82,.13)
    accentLine: Color(0x66E97A52), // rgba(233,122,82,.4)
    code: Color(0xFF1E2126),
    ok: Color(0xFF86D5A1),
    note: Color(0xFF83B4F0),
    noteSoft: Color(0x1A83B4F0), // rgba(131,180,240,.10)
    syntaxKw: Color(0xFFE08BC0),
    syntaxStr: Color(0xFF86D5A1),
    syntaxCom: Color(0xFF6E6B65),
    syntaxFn: Color(0xFF83B4F0),
    syntaxNum: Color(0xFFE0A45E),
  );

  /// Convenience accessor — `AppTokens.of(context)` instead of the longer
  /// `Theme.of(context).extension<AppTokens>()!`. Falls back to [light] if
  /// the extension is somehow missing so callers never null-check.
  static AppTokens of(BuildContext context) {
    return Theme.of(context).extension<AppTokens>() ?? AppTokens.light;
  }

  @override
  AppTokens copyWith({
    Color? bg,
    Color? panel,
    Color? panel2,
    Color? line,
    Color? line2,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentSoft,
    Color? accentLine,
    Color? code,
    Color? ok,
    Color? note,
    Color? noteSoft,
    Color? syntaxKw,
    Color? syntaxStr,
    Color? syntaxCom,
    Color? syntaxFn,
    Color? syntaxNum,
  }) {
    return AppTokens(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      panel2: panel2 ?? this.panel2,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentLine: accentLine ?? this.accentLine,
      code: code ?? this.code,
      ok: ok ?? this.ok,
      note: note ?? this.note,
      noteSoft: noteSoft ?? this.noteSoft,
      syntaxKw: syntaxKw ?? this.syntaxKw,
      syntaxStr: syntaxStr ?? this.syntaxStr,
      syntaxCom: syntaxCom ?? this.syntaxCom,
      syntaxFn: syntaxFn ?? this.syntaxFn,
      syntaxNum: syntaxNum ?? this.syntaxNum,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panel2: Color.lerp(panel2, other.panel2, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentLine: Color.lerp(accentLine, other.accentLine, t)!,
      code: Color.lerp(code, other.code, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      note: Color.lerp(note, other.note, t)!,
      noteSoft: Color.lerp(noteSoft, other.noteSoft, t)!,
      syntaxKw: Color.lerp(syntaxKw, other.syntaxKw, t)!,
      syntaxStr: Color.lerp(syntaxStr, other.syntaxStr, t)!,
      syntaxCom: Color.lerp(syntaxCom, other.syntaxCom, t)!,
      syntaxFn: Color.lerp(syntaxFn, other.syntaxFn, t)!,
      syntaxNum: Color.lerp(syntaxNum, other.syntaxNum, t)!,
    );
  }
}

/// ThemeData pair built from [AppTokens.light]/[AppTokens.dark]. Screens
/// pull chrome colors from `Theme.of(context)` (colorScheme/textTheme) and
/// palette-specific tokens (accentSoft, code, syntax*, …) from
/// `AppTokens.of(context)`.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppTokens.light, Brightness.light);
  static ThemeData get dark => _build(AppTokens.dark, Brightness.dark);

  static ThemeData _build(AppTokens tokens, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.accent,
      onPrimary: tokens.panel,
      secondary: tokens.accent,
      onSecondary: tokens.panel,
      // TOKENS.md has no distinct "error" token; accent doubles as the
      // only warm/attention color in the palette (see the warning callout
      // in README §Screens, which also uses accentSoft/accent).
      error: tokens.accent,
      onError: tokens.panel,
      surface: tokens.panel,
      onSurface: tokens.text,
    );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseTextTheme
        .apply(
          fontFamily: AppFonts.ibmPlexSans,
          bodyColor: tokens.text,
          displayColor: tokens.text,
        )
        .copyWith(
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            fontFamily: AppFonts.ibmPlexSans,
            fontSize: AppTypeScale.bodySize,
            fontWeight: AppTypeScale.bodyWeight,
            height: AppTypeScale.bodyLineHeight,
            color: tokens.text,
          ),
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontFamily: AppFonts.sourceSerif4,
            fontSize: AppTypeScale.h1Size,
            fontWeight: AppTypeScale.h1Weight,
            letterSpacing: AppTypeScale.h1LetterSpacing,
            height: AppTypeScale.h1LineHeight,
            color: tokens.text,
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontFamily: AppFonts.sourceSerif4,
            fontSize: AppTypeScale.h2Size,
            fontWeight: AppTypeScale.h2Weight,
            letterSpacing: AppTypeScale.h2LetterSpacing,
            color: tokens.text,
          ),
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontFamily: AppFonts.sourceSerif4,
            fontSize: AppTypeScale.h3Size,
            fontWeight: AppTypeScale.h3Weight,
            color: tokens.text,
          ),
        );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.bg,
      fontFamily: AppFonts.ibmPlexSans,
      textTheme: textTheme,
      dividerColor: tokens.line,
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }
}
