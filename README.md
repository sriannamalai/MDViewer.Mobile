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

**Why the submodule is pinned to a commit, not the `v0.7.0` tag:** the
plugin's `tool/checksums.txt` — which `fetch_binaries.sh` requires before
it will download anything — was committed to the library's `main` branch
*after* the `v0.7.0` tag was cut, so the tag's copy of that file has no
entries and `fetch_binaries.sh` refuses to fetch. `vendor/markdownviewer`
is pinned to `f086085` (`main`, "chore(flutter): pin v0.7.0 mobile
artifact checksums; plugin version 0.7.0"), the first commit whose
`checksums.txt` actually has the `libmdviewer-0.7.0-*.zip` entries. It
still resolves to the v0.7.0 release artifacts — this is a checkout-ref
fix, not a version change.

1. **Prerequisites**: Flutter 3.44.x, Xcode + an iOS simulator runtime,
   Android SDK + an AVD (or a physical device for either platform),
   CocoaPods.
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

## Known limitations (v1)

- **"Open with MDViewer" opens the file alone.** A document handed over
  by the OS (share sheet, Files app, another app) renders fully, but its
  *relative* images and links have no folder to resolve against, so they
  show as unresolved placeholders. Point the app at the containing folder
  ("Choose folder") to get relative content.
- **One folder vault at a time.** Picking a new folder replaces the
  previous grant; there is no multi-vault list. The bundled Samples vault
  is always present alongside it.
- **Internal relative `.md` links navigate on iOS only.** On Android the
  WebView collapses a tapped relative link's URL before the app sees it
  (`loadHtmlString` has no base URL), so the target is unrecoverable —
  the tap is deliberately a no-op there rather than a blank page.
- **Wiki-links (`[[Like This]]`) do not navigate** — they render styled
  but inert. Use the Library tree or Search to move between documents.
- **`mailto:` / `tel:` links are declined** — v1 opens only `http(s)`
  links (in the system browser) and vault-relative `.md` links (in the
  Reader).
- **Share exports self-contained HTML only** — no PDF export yet.
- **No code-block language/Copy header** — the design shows one; the
  library's HTML render doesn't emit it yet (ledgered library gap).
- **The reader renders with the system font stack** — the webview document
  doesn't use the design's Source Serif 4 / IBM Plex Sans / JetBrains Mono
  (ledgered library gap); the app chrome around it does bundle those fonts.
- Read-only by design: no editing, no file management, no sync.

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
