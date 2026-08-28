# Changelog

All notable changes to this project are documented in this file, reconstructed
from the git history (there is no prior `CHANGELOG.md`).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This app does not cut its own semantic-version releases — `app/pubspec.yaml`
has stayed at `1.0.0+1` throughout — so entries are grouped by the milestone
labels this repo already uses in its own `README.md`/`AGENTS.md` (**v1**, the
Webview-only reader; **v2**, the dual-engine reader), plus point-releases for
notable additions shipped after a milestone closed.

## [v2.2] - 2026-08-28

Cross-Repo Rendering Engine Synchronization Plan, Phase 2: consumes the
core library's gap-train fixes, closes the auto-Webview-on-Mermaid
fallback, and adds a CI/release-artifact pipeline.

### Added

- **Native Mermaid rendering.** `MermaidBridge`
  (`lib/src/render/mermaid_bridge.dart`) drives a hidden offscreen
  `webview_flutter` instance running the library's `mermaid.js` +
  `mermaid-bridge.js` assets; each diagram renders to SVG via
  `mdvRenderMermaid` and displays through `flutter_svg`, falling back to
  the library's placeholder on any failure. Dropped the
  auto-Webview-on-Mermaid rule in `engine_policy.dart` — native is now
  always the default engine, Mermaid included.
- **`#fragment`-only link navigation** — a new `LinkFragment` decision in
  `link_policy.dart`, resolved against the current document's
  `MdvHeading.anchorId`s (heading anchors only; see Known limitations).
- **`.github/workflows/ci.yml` / `release.yml`** — format/analyze/test +
  Android/iOS build verification, and a release-artifact pipeline
  (APK/AAB + unsigned iOS archive + checksums) mirroring
  `MarkDownViewer`'s release strategy.
- `CHANGELOG.md` (this file).

### Changed

- Proposed and got merged a small additive plugin API,
  `MdvFootnoteRefTapCallback`/`onFootnoteRefTap` on
  `MdvRenderScope`/`MdvDocumentAdapter`/`MdvDocumentView` (mirrors
  `onLinkTap`) — the typed model had no way to intercept a footnote-ref
  tap at all before this. Footnote-ref taps now jump to the trailing
  footnotes section (not yet the exact definition — see Known
  limitations).
- Bumped the `vendor/markdownviewer` submodule to `flutter-v0.11.0`
  (`v0.11.0` native binaries) — consumes the CRLF code-fence highlighting
  fix (removed the corresponding native-engine limitation note),
  `FootnoteRef.DefID`/`Tree.FootnoteByIndex`, and `mermaid-bridge.js`.

## [v2.1] - 2026-08-28

Native-engine image support catches up with Webview, plus a persistent
project-memory doc for agents.

### Added

- **Native SVG images.** `NativeImageResolver` (`lib/src/render/native_images.dart`)
  rasterizes `.svg` bytes via a pinned-exact `flutter_svg` dependency
  (`vg.loadPicture` + canvas-scaled `Picture.toImage`) into a custom
  `ImageProvider`, instead of declining to the alt-text placeholder. Closes
  the "SVG images show as alt text" native-engine gap.

### Docs

- `AGENTS.md` — persistent project memory (architecture, sibling-repo
  relationships, finished work, known limitations, roadmap).

## [v2] - 2026-08-14

The native reader: a second, default rendering engine next to Webview, built
on the library's v0.10 render tree.

### Added

- **Engine policy** (`render/engine_policy.dart`) — Mermaid-detection walk,
  per-document engine override with persisted precedence, and the
  preference keys backing it.
- **Native document widget** over `MdvDocumentAdapter`, with a vault-backed
  async image resolver.
- **Native scroll integration** — scroll-position restore, scrollspy derived
  from item positions, and engine-neutral line persistence shared with the
  Webview engine.
- **Dual-engine Reader** — native rendering by default, automatic fallback
  to Webview for documents containing Mermaid diagrams, a manual per-document
  engine switch (persisted across relaunch), and a native link policy.

### Changed

- Bumped the `vendor/markdownviewer` submodule to `flutter-v0.10.1`
  (`v0.10.0` native binaries) and added the `scrollable_positioned_list`
  dependency the native scroll integration is built on.
- `dart format` reconciliation of two v1 test files against the Dart 3.13
  formatter.
- README rewritten for the v2 dual-engine reader: engine descriptions and a
  per-engine "Known limitations" section; version references updated to
  0.10.x.

### Fixed

- Gated native bottom-snap behavior on scrollable documents; added a
  parse-once assertion.
- Rescoped the Android Webview relative-link no-op to the Webview engine
  only, and noted the native-engine CRLF code-fence highlighting gap.
- Loaded the library palette so native code fences keep syntax highlighting.
- Pinned Reader palette wiring with a reader-level regression test; restored
  render-tree document attachment.

## [v1] - 2026-08-09 to 2026-08-11

The first working app: Webview-only reader, vault-backed library, search,
and the outline sheet.

### Added

- Complete visual design and a splash screen design.
- Flutter scaffold over the released `libmdviewer` v0.7.0 (submodule,
  bootstrap script, design tokens, bundled fonts and icons).
- Vault layer — folder-access platform channels, the vault index, bundled
  sample documents, and recents persistence.
- App shell — splash, tab bar, navigation, settings, theme.
- Library screen — header, search field, vault file tree, recents list,
  empty state.
- Reader — Webview `loadHtmlString` rendering, scrollspy, bottom bar, share,
  link/image resolver.
- Outline sheet — scrollspy rows with live highlighting and tap-to-scroll.
- Search screen, the vault search engine, and OS "Open with…" registration.

### Fixed

- iOS vault channel root-path check and a concurrent `pickFolder` guard.
- Outline sheet drop shadow and empty-state padding; `accentSoft` test.
- `openedFile` recent-file lookup, scrollspy line fallback, and the
  "Open with…" delivery retry queue.
- Android SAF folder-grant crash (`takePersistableUriPermission` flags).
- Reader hairline fill height, image reuse on re-render/share, and a
  stricter navigation policy.
- Reader navigation policy — decline `data:` links, exact `about:blank`
  matching on iOS.
- Reader reading-progress percent no longer gets ellipsized away; dropped a
  redundant pre-read on open.
- Bridged the code-block Copy button through a `CodeCopy` JS channel; scaled
  the code header with the Aa text-size control.

### Changed

- Promoted remaining hardcoded type sizes into `AppTypeScale`.
- Capped aggregate image prefetch at 32MB; assorted comment/README
  precision fixes.
- Bumped the library to `flutter-v0.8.1`, consuming its `extraCss`,
  `codeHeader`, and pre-resolve helpers.
- README — added the `flutter test` step, an iOS first-build retry note,
  and the v1 "Known limitations" section.
