# AGENTS.md — MDViewer.Mobile

Persistent project memory for agents. Update whenever architecture,
status, or roadmap materially changes.

## What this project is
A read-only Markdown viewer for iOS/Android, built with **Flutter**,
consuming the [MarkDownViewer](https://github.com/sriannamalai/markdownviewer)
Go library through its Flutter plugin (`flutter/mdviewer`, vendored here as
a git submodule at `vendor/markdownviewer`, pinned to tag **`flutter-v0.10.1`**
— the plugin release; underlying native binaries are v0.10.0). 34 commits,
app version `1.0.0+1`, currently at "v2" per its own README (dual-engine
reader) — most mature of the two apps.

## The sibling repos (the bigger picture)
- **`~/Developer/OpenSource/MarkDownViewer`** — the rendering engine. This
  app is the most advanced consumer of it: it's the first host to exercise
  the v0.10 **native render tree** (`MdvDocumentView`/`MdvDocumentAdapter`)
  end-to-end, rather than just HTML-in-a-webview. Bugs found here often get
  fixed upstream first, then this repo bumps the `vendor/markdownviewer`
  submodule to a new `flutter-v<ver>` tag (never a raw commit SHA — see
  that repo's `CONTRIBUTING.md`).
- **`~/Developer/OpenSource/MDViewer.Desktop`** — the Tauri sibling app.
  Same design identity (`design/TOKENS.md` here is byte-identical to that
  repo's copy — keep in sync on change) and the same underlying rendering
  engine, but Desktop still renders HTML into a webview via the C ABI and
  has not adopted the render tree. This app is architecturally ahead of
  Desktop on that axis; consider porting lessons back when Desktop tackles
  native rendering.

## Architecture
- **`app/lib/`** (Flutter/Dart):
  - `screens/`: `splash.dart`/`splash_gate.dart`, `library.dart` (vault file
    tree + recents), `reader.dart` (the document view), `native_doc_view.dart`,
    `outline_sheet.dart` (scrollspy bottom sheet), `search.dart`,
    `settings.dart`, `shell.dart` (tab bar / navigation host).
  - `render/`: `renderer.dart`, `engine_policy.dart` (native vs. Webview
    selection — Mermaid auto-selects Webview), `resolver.dart` (link/image
    resolution against the vault), `native_images.dart`, `native_palette.dart`
    (theme→plugin palette bridge), `link_policy.dart`, `scrollspy.dart`,
    `codecopy.dart` (JS-channel bridge for the Webview engine's Copy button).
  - `vault/`: folder-access abstraction — `vault_provider.dart` and
    platform/opened-file/sample implementations, `vault_index.dart`,
    `search.dart`, `recents_store.dart`, `open_with_channel.dart` +
    `open_with_delivery_queue.dart` (OS "Open with…" handoff).
  - `state/`: `app_state.dart`, `doc_state.dart`, `vault_state.dart`
    (provider-based state management — `package:provider`).
  - `widgets/`, `util/`, `tokens.dart`, `navigation.dart`,
    `mdviewer_version.dart` (plugin↔library version handshake check).
- **Dual-engine reader** (the core architectural feature): **Native**
  (via the plugin's typed render tree + `MdvDocumentAdapter`, using
  `scrollable_positioned_list` for scroll control) is the default engine
  for every document. **Webview** (`webview_flutter`, the original
  `loadHtmlString` pipeline) is always available as a fallback/escape
  hatch — auto-selected when a document contains Mermaid (native has no
  diagram renderer yet), and switchable per-document by hand via the
  Reader's "Aa" sheet → Engine row; the choice persists across relaunch.
- Design spec in `design/` mirrors the Desktop repo's structure:
  `design/README.md` (5 screens: splash, library, reader, outline sheet,
  search — phone ergonomics: bottom-anchored controls, sheets not side
  panels, 44px+ touch targets) and `design/TOKENS.md` (shared tokens, with
  mobile-scale prose type deltas). Treat as normative.

## Finished so far
Chronologically (see `git log --oneline`), grouped:
- **Foundation**: Flutter scaffold over released `libmdviewer` v0.7.0
  (submodule + bootstrap script + tokens/fonts/icons); vault layer (folder
  access channels, index, bundled samples, persistence); app shell (splash,
  tab bar, navigation, settings, theme).
- **v1 screens**: Library (header, search field, vault tree, recents, empty
  state); Reader (Webview render, scrollspy, bottom bar, share, resolver);
  Outline sheet (rows, live scrollspy highlight, tap-to-scroll); Search
  screen + vault search engine + OS "open with" registration.
- **v1 hardening**: Android SAF folder-grant crash fix, iOS vault
  root-path/concurrency guards, nav-policy tightening (decline `data:`
  links, exact `about:blank` matching on iOS), type-scale consolidation,
  image reuse/prefetch caps, percent-display fix.
- **Library bump train**: to `flutter-v0.8.1` (consumed `extraCss`,
  `codeHeader`, pre-resolve helpers) → `flutter-v0.10.1`/v0.10.0 binaries +
  `scrollable_positioned_list` dependency.
- **v2 — the native reader**: engine policy (Mermaid-detection walk,
  per-doc override, persisted prefs); native document widget over
  `MdvDocumentAdapter` + vault-backed async image resolver; native scroll
  integration (position restore, scrollspy from item positions,
  engine-neutral line persistence); the dual-engine Reader itself
  (native default, Mermaid auto-Webview, per-doc switch, native link
  policy); hardening fixes (bottom-snap gating, palette wiring for native
  code-fence syntax highlighting, Android Webview relative-link rescoping,
  `renderTree` doc-attachment fix).

## Known limitations (v2, per README — organized by engine)
**Native engine only:** footnote refs don't jump to definition (library
gap, not app-fixable yet); pure `#fragment` links are inert (native nav is
line-based, not anchor-based); reading-progress % is block-weighted, not
pixel-accurate;
internal relative `.md` links push a new Reader screen instead of
replacing it (a real cross-engine back-stack difference vs. Webview on
iOS); CRLF-line-ending code fences lose syntax highlighting (library
fail-closed behavior).
**Both engines:** "Open with MDViewer" alone can't resolve relative
links/images (no folder context) — user must "Choose folder" instead; one
folder vault at a time (no multi-vault list); wiki-links render but don't
navigate; `mailto:`/`tel:` links declined; export is self-contained HTML
only (no PDF yet); read-only by design (no editing/file management/sync).
**Webview engine only:** internal relative `.md` links only navigate on
iOS (Android's `loadHtmlString` has no base URL, so taps are a deliberate
no-op there — switch to Native to navigate on Android); Webview-rendered
document body uses the system font stack, not the design's custom fonts
(app chrome still uses the bundled fonts regardless of engine).

## Next items (proposed, mirrors the core library's own roadmap)
Since this app is explicitly the "native-render validation" testbed the
core library's roadmap calls for, its own next steps are largely the same
list, from this app's side:
1. **Close native-engine gaps** discovered so far: footnote
   jump-to-definition (needs a scroll-controller design — likely a
   library-side primitive first), `#fragment`-only link navigation,
   back-stack harmonization for relative `.md` links (native push vs.
   Webview replace).
   - **Done:** SVG image decoding — `NativeImageResolver`
     (`lib/src/render/native_images.dart`) now rasterizes `.svg` bytes via
     a pinned-exact `flutter_svg` dependency (`vg.loadPicture` +
     canvas-scaled `Picture.toImage`) into a small custom `ImageProvider`,
     instead of declining to the alt-text placeholder.
2. **Mermaid native rendering** — this app is the intended first prototype
   site for the library's offscreen-webview→SVG mermaid service; once
   available, wire it as the native engine's `diagram` builder and drop
   the auto-Webview-on-Mermaid rule.
3. **CRLF code-fence highlighting** — track the library fix; re-pin once
   available.
4. Multi-vault support and PDF export are explicitly out of scope for the
   current version but flagged as desired follow-ups per the "Known
   limitations" list.
5. Keep the `vendor/markdownviewer` submodule pin current as the library
   ships new `flutter-v<ver>` tags — check the library's `CHANGELOG.md`
   for Flutter-relevant changes each time.

## Build & run
```bash
scripts/bootstrap.sh          # init submodule + fetch/verify libmdviewer binaries (idempotent)
cd app
flutter pub get
flutter run                   # pick iOS simulator or Android emulator/device
flutter test                  # no device needed; renderer faked where native lib would be required
```
Prerequisites: Flutter 3.44.x, Xcode + iOS 15.0+ simulator runtime, Android
SDK + AVD, CocoaPods. Known iOS quirk: first build after fresh
`pod install` can fail on `-force_load` path resolution — just rebuild.
Launcher icons regenerate via `flutter_launcher_icons` from
`design/assets/icon-tile.svg` (see README's "Regenerating launcher icons").
