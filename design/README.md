# Handoff: MDViewer Mobile UI — "MarkDownViewer"

## Overview
The mobile companion to MDViewer.Desktop: five screens — splash, library, reader, outline sheet, search. A read-only Markdown viewer with the **same visual identity** (tokens, type, icon) rebuilt around phone ergonomics — bottom-anchored controls, one document at a time, sheets instead of side panels, 44px+ touch targets.

## About the design files
`reference/MarkdownViewerMobile.dc.html` is a **design reference built in HTML** (open in a browser; keep `support.js` and `ios-frame.jsx` beside it — the iPhone bezel is presentation scaffolding, not part of the design). Recreate the four screens natively (SwiftUI / Jetpack Compose / Flutter — implementer's choice). Screens are designed at 402×874 (iPhone-class); all values are CSS px at 1×.

## Fidelity
**High-fidelity.** Colors, typography and spacing are final, per `TOKENS.md` (shared with the desktop repo — single source of identity). Prose type is slightly larger than desktop for arm's-length reading: body 15px/1.68, H1 27px, H2 19px, code 12px. Status bar / home indicator / keyboard are OS-drawn; everything else below is the app.

## Screens

### 00 · Splash
- Full-screen gradient: `linear-gradient(168deg, #33373f 0%, #1d1f25 42%, #131418 72%, #0f1013 100%)` (icon-tile charcoal family). Soft coral radial glow centered behind the logo: `rgba(226,113,74,.20) → transparent @ 68%`, ~380px diameter.
- Centered logo: bracket mark at 132px (same SVG as `assets/icon.svg`) with drop shadow `0 10px 34px rgba(226,113,74,.22)`; wordmark below 26px/600 — "MarkDown" `#e9e7e2`, "Viewer" `#75726b`/500; tagline 12px `text2` "Markdown, rendered beautifully — offline".
- Bottom (44px above edge): 104×3 loading bar — track `line2`, fill `linear-gradient(90deg, #ffb27d, #e2714a)`, indeterminate sweep; version string mono 10.5px `text3` beneath.
- Always dark regardless of theme; OS status bar light-content. Dismisses to Library when the vault index is ready.

### 01 · Library
- **Header** (white `panel`, 1px `line` bottom border, sits under the OS status bar): 26px app icon tile (charcoal gradient, bracket mark) + wordmark 17px/600 ("MarkDown" `text`, "Viewer" `text3`/500), right 34px circular theme toggle (`panel2` fill).
- **Search field**: 40px, radius 10, `panel2` bg, 1px `line` border, placeholder "Search files and headings" 14px `text3`.
- **File tree**: uppercase section label (11px/600/.09em `text3`); rows 48px, radius 10, padding 0 8: disclosure caret 10px, folder glyph, name 15px `text`; right-aligned meta (child count or ›) mono 12px `text3`. Markdown files badged "M" mono 11px `accent`, indented 22–30px under folders. Active file: `accentSoft` fill, `accent` text/500. "Recent" section: same rows with relative-time meta (2h, 1d).
- **Tab bar**: 88px incl. home-indicator clearance, `rgba(255,255,255,.92)` + 12px blur, 1px `line` top border; three equal items (icon 19px + 10.5px label): Library / Search / Settings; active `accent`, inactive `text3`.

### 02 · Reader
- **Header** (blurred `bg` @ .94, 1px `line2` bottom border): 38px back button ‹ (`accent`), centered stack — filename 14px/600 + "vault · read time" mono 10.5px `text3`, 38px share ⇪ right.
- **Progress hairline**: 2px `line2` track under the header, `accent` fill = scroll progress.
- **Content** (padding 22×20): markdown per desktop language, mobile scale — H1 Source Serif 4 27/700; badge row (joined key/value pills mono 9.5px, `panel2`/`text2` + `accent`/white); body 15px/1.68; warning callout (radius 10, `accentSoft`, ⚠ + uppercase 11px title); H2 19/600 with `line` underline; code blocks radius 10 with language/Copy header, mono 12px.
- **Bottom bar** (78px incl. clearance, same blur treatment): "☰ Outline" pill 40px high radius 20 `panel2` 13px/500; right: current section + % mono 11px `text3`, then 40px circular "Aa" text-size control. This bar is the thumb home — everything reachable one-handed.

### 03 · Outline sheet (over Reader)
- Veil `rgba(10,11,12,.28)`; content behind blurs 1px @ 55% opacity.
- **Sheet**: white `panel`, radius 18 top corners, shadow `0 -12px 40px rgba(0,0,0,.18)`, 40×4 grabber `line` centered; header row — uppercase "On this page" label left, "1,140 words · 5 min" mono 11px `text3` right.
- **Outline rows**: 44px, radius 10, 15px text; H1 500 `text2`, H2 indent 28px, H3 indent 42px `text3`; active section `accentSoft` fill + `accent`/600. Tap scrolls and dismisses.

### 04 · Search (dark theme shown)
- **Header** (`panel` dark, 1px `line` bottom border): 40px query field radius 10, `panel2` bg, **`accentLine` focused border**, mono query text + `accent` caret, ✕ clear; filter chips below (Aa / .* / Whole word) — 20px-radius pills, active `accentSoft`+`accent`, inactive 1px `line` border `text3`.
- **Results**: count line 11px `text3`; cards radius 10 padding 10×12 (selected `accentSoft`): filename 12px/500 + `L<line>` mono right; snippet mono 11.5px `text2` with match substring in `accent`.
- OS keyboard sits below; results scroll behind it.

## Interactions & behavior
- Navigation: Library → tap file → Reader (push). Back ‹ returns. Tabs switch root screens.
- Reader bottom bar: Outline opens the sheet (spring, ~0.3s); Aa opens a text-size stepper; share ⇪ exports (PDF / self-contained HTML, same options as desktop).
- Outline sheet: drag grabber or veil-tap dismisses; rows scrollspy-highlight while reading.
- Progress hairline and "section · %" update on scroll.
- Theme toggle in Library header: light ⇄ dark, same token swap as desktop; respect OS setting by default.
- All tap targets ≥44px. No hover states — pressed states use the hover fills from TOKENS (`panel2` / `accentSoft`).

## State management
`theme` · `route` (library/reader/search/settings) · `activeDoc` + per-doc scroll % and active heading · `outlineSheetOpen` · `searchQuery` + filters + results · `textScale`. Vault index, recents and search come from the host filesystem + renderer (same engine contract as desktop: CommonMark+GFM, offline KaTeX/mermaid, sanitized by default).

## Design tokens
See [`TOKENS.md`](TOKENS.md). Mobile deltas only: row height 44–48px · sheet radius 18 · pill controls radius 20 · bar blur `blur(12px)` at .92–.94 surface opacity.

## Assets
- `assets/icon.svg` / `assets/icon-tile.svg` — the bracket mark (export iOS/Android icon sets from icon-tile)
- Fonts: IBM Plex Sans, Source Serif 4, JetBrains Mono — bundle with the app, never network-load.

## Screenshots
`screenshots/` — 2× captures: 00-splash · 01-library · 02-reader · 03-outline-sheet · 04-search-dark.

## Files
- `reference/MarkdownViewerMobile.dc.html` — the design source (all five screens)
- `reference/support.js`, `reference/ios-frame.jsx` — prototype runtime + bezel scaffolding (not part of the design)
