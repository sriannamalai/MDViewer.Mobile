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
library's `flutter-v0.11.0` tag (CRLF code-fence highlighting fix, the
`FootnoteRef.DefID`/`Tree.FootnoteByIndex` footnote-definition linkage,
the `mermaid-bridge.js` offscreen-rendering primitive, and an additive
`onFootnoteRefTap` plugin callback), with matching native binaries at
`v0.11.0`. Since v0.7.1 the library cuts a `flutter-vX.Y.Z` tag on the
commit whose plugin `pubspec.yaml` and `tool/checksums.txt` both carry
that release — so the tag's `fetch_binaries.sh` can verify and download
the matching `libmdviewer-0.11.0-*.zip` release artifacts directly.

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

## Known limitations (v2.3, per README — organized by engine)

The Reader has two rendering engines. **Native** (the plugin's typed
render tree, via `MdvDocumentAdapter`) is the default for every document
— including ones with a Mermaid diagram, which the native engine now
renders itself (see "Native Mermaid rendering" below); Mermaid no longer
auto-selects Webview. **Webview** (the original `loadHtmlString`
pipeline) is always available as a fallback, and any document can be
switched to it by hand. The per-document **Engine** row in the Aa sheet
is the escape hatch for every native-only limitation below: switching to
Webview picks up the feature immediately, on that document only, and the
choice persists across relaunch.

**Native Mermaid rendering.** `MermaidBridge` (`lib/src/render/
mermaid_bridge.dart`) drives a hidden, offscreen `webview_flutter`
instance running the library's `mermaid.js` + `mermaid-bridge.js` assets,
created lazily only for a document that actually contains a diagram
(`treeContainsMermaid`). Each diagram's Mermaid source renders to an SVG
string via `mdvRenderMermaid`, displayed with `flutter_svg`; any failure
(no reachable `libmdviewer`, a malformed diagram, a bridge timeout)
falls back to the library's bordered placeholder, never a crash. A
diagram also re-renders on a light/dark theme flip AFTER it has already
rendered, comparing the ambient brightness against the theme its cached
request was issued for (`MermaidDiagramView`) — every native block
restyles in place on a theme flip, diagrams included.

Native engine only:

- **Pure `#fragment` links jump to a matching HEADING only.** Native
  navigation resolves a fragment against `MdvHeading.anchorId` (the
  same slugs headings carry); a fragment that isn't a heading anchor
  (e.g. a custom raw-HTML `id`) shows a brief snackbar hint ("This link
  points to a location this app can't jump to directly") instead of a
  silent no-op, but still can't jump there directly — that needs a
  plugin-side scroll-target primitive (issue #4). The Webview engine
  handles any in-page anchor via the browser's own DOM lookup.
- **Footnote-reference taps jump to the footnotes section, not the
  exact definition.** `MdvDocumentAdapter` renders every definition
  inside ONE trailing list item (no per-definition scroll target), so a
  tap on any in-text footnote marker scrolls there — close, but not a
  precise landing when a document has several footnotes (issue #3,
  needs a plugin-side change). The Webview engine still jumps to the
  exact definition in-page.

Both engines:

- **"Open with MDViewer" opens the file alone.** A document handed over
  by the OS (share sheet, Files app, another app) renders fully, but its
  *relative* images and links have no folder to resolve against. The
  Reader now detects this and shows a dismissible banner prompting
  "Choose folder" (re-opening the same document from the newly-picked
  vault when its filename matches exactly one file there) instead of
  silently showing broken placeholders — iOS's sandboxing still rules
  out resolving them without that folder pick at all.
- **Multiple folder vaults are supported** (`VaultState.vaultGrants`),
  switchable from the Library's vault chips; the bundled Samples vault
  is always present alongside them. One known simplification: a
  folder-vault document only resolves relative links/images while ITS
  vault is the active one (`VaultSource`/`VaultEntry` don't carry a
  per-instance vault id yet).
- **`mailto:` / `tel:` links show a brief "Open in Mail/Phone app?"
  confirmation** before handing off to the OS, on both engines.
- **Share offers HTML or PDF export** — PDF converts the same
  Webview-rendered HTML the HTML export produces, via the `printing`
  package's `Printing.convertHtml`.
- Read-only by design: no editing, no file management, no sync.

Webview engine only:

- **Internal relative `.md` links only navigate on iOS.** On Android
  the WebView collapses a tapped relative link's URL before the app
  sees it (`loadHtmlString` has no base URL), so the tap is a
  deliberate no-op there — switch the document to Native to navigate
  on Android. A `baseUrl`-based fix is identified (issue #12) but needs
  on-device verification it doesn't also change what iOS's WKWebView
  reports for its own page load before it's safe to ship.

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
