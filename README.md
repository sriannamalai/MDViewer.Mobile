# MDViewer.Mobile
Mobile companion app for MDViewer — viewing MarkDown files on iOS and Android using the modern MarkDownViewer built by Sri.

## Design

The complete UI design lives in [`design/`](design/):

- [`design/README.md`](design/README.md) — full design specification: screens, measurements, interactions
- [`design/TOKENS.md`](design/TOKENS.md) — color tokens (light + dark), typography and spacing (shared with MDViewer.Desktop)
- [`design/assets/`](design/assets/) — app icon SVGs
- [`design/screenshots/`](design/screenshots/) — reference captures of all four screens
- [`design/reference/`](design/reference/) — the HTML design prototype (open `MarkdownViewerMobile.dc.html` in a browser, keep the sibling files beside it)

Same visual identity as the desktop app; compact, thumb-reach ergonomics. Implementation agents: start with `design/README.md`.

## Build & run

The app consumes the [MarkDownViewer](https://github.com/sriannamalai/markdownviewer)
rendering engine as a git submodule (`vendor/markdownviewer`) plus its
released, checksum-verified mobile binaries — nothing here builds Go or
touches a Go toolchain.

**How the submodule is pinned:** `vendor/markdownviewer` is pinned to the
library's `flutter-v0.10.1` tag. Since v0.7.1 the library cuts a
`flutter-vX.Y.Z` tag on the commit whose plugin `pubspec.yaml` and
`tool/checksums.txt` both carry that release — so the tag's
`fetch_binaries.sh` can verify and download the matching
`libmdviewer-0.10.0-*.zip` release artifacts directly (0.10.1 is a
Dart-only plugin release with no artifact set of its own — the pinned
binaries stay v0.10.0). (The v0.7.0 era predated those tags: the
checksums landed on `main` *after* the `v0.7.0` tag was cut, which forced
a raw-commit pin back then. That rationale is obsolete — pin
`flutter-v*` tags going forward.)

1. **Prerequisites**: Flutter 3.44.x, Xcode + an iOS simulator runtime
   (iOS 15.0+ deployment target), Android SDK + an AVD (or a physical
   device for either platform), CocoaPods.
2. **Bootstrap** — from the repo root, once per fresh checkout (idempotent,
   safe to re-run):

   ```bash
   scripts/bootstrap.sh
   ```

   This initializes `vendor/markdownviewer` and downloads+verifies the
   release-pinned `libmdviewer` binaries into the plugin's platform dirs
   (`ios/Frameworks/`, `android/src/main/jniLibs/`) — see the plugin's own
   README at `vendor/markdownviewer/flutter/mdviewer/README.md` for what
   it installs and why.
3. **Run**:

   ```bash
   cd app
   flutter pub get
   flutter run   # pick an iOS simulator or Android emulator/device
   ```

   iOS links `libmdviewer` into the app binary via the plugin's podspec
   (`-force_load`, applied automatically through CocoaPods' generated
   xcconfig — no manual Xcode changes needed); Android loads the bundled
   `.so` from `jniLibs` at runtime. Both are exercised by
   `flutter run`/`flutter build`.

   Known iOS quirk: the *first* build after a fresh `pod install` can fail
   with "Build input file cannot be found" around the `-force_load` path
   (an Xcode build-ordering issue). Just build again — the second build
   succeeds.

4. **Test** (no device needed — the renderer is faked where the native
   library would be required):

   ```bash
   cd app
   flutter test
   ```

## Known limitations (v2)

The Reader has two rendering engines. **Native** (the plugin's typed
render tree, via `MdvDocumentAdapter`) is the default for every document.
**Webview** (the original `loadHtmlString` pipeline) is always available
as a fallback — a document containing a Mermaid diagram auto-selects it
(native has no Mermaid renderer yet; a fast-follow will render diagrams
to an offscreen SVG instead), and any document can be switched to it by
hand. The per-document **Engine** row in the Aa sheet is the escape
hatch for every native-only limitation below: switching to Webview picks
up the feature immediately, on that document only, and the choice
persists across relaunch.

Native engine only:

- **Footnote references don't jump.** The definitions render (in a
  trailing section), but tapping an in-text footnote marker does nothing
  — the rendering library doesn't resolve footnote-ref taps yet (v1
  descope in the library, not this app). The Webview engine handles them
  in-page.
- **SVG images show as alt text.** Flutter's image pipeline can't decode
  SVG, so relative `.svg` targets decline to the alt-text placeholder
  instead of rendering. The Webview engine renders them.
- **Pure `#fragment` links are inert.** Native navigation and scrollspy
  are line-based, not anchor-based, so a link that is only a fragment
  (no file target) does nothing. The Webview engine handles in-page
  anchor jumps.
- **Progress / hairline % is a block-weighted approximation**, not a
  pixel-accurate scroll fraction — every block counts equally regardless
  of its rendered height. It snaps to exactly 100% at the bottom of a
  document that's taller than the viewport (matching what the Webview
  engine reports at its scroll end); a document that fits entirely
  inside the viewport never scrolls, so it reports 0%, same as Webview.
- **Internal relative `.md` links push a new Reader screen** (back
  returns to the linking document), while the Webview engine still
  *replaces* the current Reader with the target (iOS — see the Webview
  note below for Android). This is a real cross-engine back-stack
  difference, carried forward pending harmonization — switching engines
  mid-document doesn't change how the *next* link tap navigates.
- **CRLF-line-ending code fences render without syntax highlighting**
  on the native engine (the library's token runs fail closed on CRLF;
  the code still renders as plain monospace text). The Webview engine
  highlights the same fence normally.

Both engines:

- **"Open with MDViewer" opens the file alone.** A document handed over
  by the OS (share sheet, Files app, another app) renders fully, but its
  *relative* images and links have no folder to resolve against, so they
  show as unresolved placeholders. Point the app at the containing folder
  ("Choose folder") to get relative content.
- **One folder vault at a time.** Picking a new folder replaces the
  previous grant; there is no multi-vault list. The bundled Samples vault
  is always present alongside it.
- **Wiki-links (`[[Like This]]`) do not navigate** — they render styled
  but inert. Use the Library tree or Search to move between documents.
- **`mailto:` / `tel:` links are declined** — the Reader opens only
  `http(s)` links (in the system browser) and vault-relative `.md` links
  (in the Reader).
- **Share exports self-contained HTML only** — no PDF export yet.
- Read-only by design: no editing, no file management, no sync.

Webview engine only:

- **Internal relative `.md` links only navigate on iOS.** On Android
  the WebView collapses a tapped relative link's URL before the app
  sees it (`loadHtmlString` has no base URL), so the tap is a
  deliberate no-op there — switch the document to Native to navigate
  on Android.
- **The Webview-rendered document uses the system font stack**, not the
  design's Source Serif 4 / IBM Plex Sans / JetBrains Mono (ledgered
  library gap) — the app chrome around it bundles those fonts regardless
  of which engine is rendering the document body.

### Regenerating launcher icons

Launcher icons are generated from `design/assets/icon-tile.svg` via
[`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons),
configured in `app/pubspec.yaml`. To regenerate after a mark change:

```bash
# Full tile (background + bracket) → iOS icon + Android legacy icon
rsvg-convert -w 1024 -h 1024 design/assets/icon-tile.svg -o app/assets/icon/icon.png

# Bracket mark only, transparent background → Android adaptive foreground
# (strip the two <rect> background/border elements from icon-tile.svg first;
# the bracket <path> elements' own bounding box already sits inside the
# adaptive-icon safe zone at the source viewBox's proportions)
rsvg-convert -w 1024 -h 1024 <bracket-only-svg> -o app/assets/icon/icon-foreground.png

cd app && dart run flutter_launcher_icons
```
