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
