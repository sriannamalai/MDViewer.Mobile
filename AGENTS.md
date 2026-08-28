# AGENTS.md — MDViewer.Mobile

Persistent project memory for agents. Update whenever architecture,
status, or roadmap materially changes.

## What this project is
A read-only Markdown viewer for iOS/Android, built with **Flutter**,
consuming the [MarkDownViewer](https://github.com/sriannamalai/markdownviewer)
Go library through its Flutter plugin (`flutter/mdviewer`, vendored here as
a git submodule at `vendor/markdownviewer` — currently pinned to a raw
commit on the library's `sync/core-engine-gaps` branch, not yet a
`flutter-v*` tag; see README's "How the submodule is pinned"; underlying
native binaries stay v0.10.0). ~40 commits, app version `1.0.0+1`,
currently at "v2" per its own README (dual-engine reader) — most mature
of the two apps.

## Engine version sync (Cross-Repo Rendering Engine Synchronization Plan)
**Finalized specialization decision:** Mobile is the native render-tree +
dual-engine **flagship** by design — it is the only one of the two demo
apps that exercises all three of the library's capabilities (the native
render tree as the default, full HTML output, and live dual-engine
switching), and stays that way going forward rather than converging with
Desktop's HTML/webview architecture (Desktop's own `AGENTS.md` records the
symmetric decision: Desktop stays the HTML/webview flagship, deliberately
not adopting the render tree — see that repo's project memory for the
full rationale). Practical implication: every native-engine gap this app
finds is this app's own to close (in the library first if it needs a new
primitive, then here) — it is not a signal to move Mobile onto Desktop's
HTML pipeline instead.

## The sibling repos (the bigger picture)
- **`~/Developer/OpenSource/MarkDownViewer`** — the rendering engine. This
  app is the most advanced consumer of it: it's the first host to exercise
  the v0.10 **native render tree** (`MdvDocumentView`/`MdvDocumentAdapter`)
  end-to-end, rather than just HTML-in-a-webview. Bugs found here often get
  fixed upstream first, then this repo bumps the `vendor/markdownviewer`
  submodule to a new `flutter-v<ver>` tag (a raw commit SHA is a temporary
  exception while the current fixes are pinned pre-tag — see that repo's
  `CONTRIBUTING.md`; re-pin to a tag once one exists).
- **`~/Developer/OpenSource/MDViewer.Desktop`** — the Tauri sibling app.
  Same design identity (`design/TOKENS.md` here is byte-identical to that
  repo's copy — keep in sync on change) and the same underlying rendering
  engine, but Desktop keeps HTML/webview rendering as ITS flagship by
  design (see "Engine version sync" above) and does not adopt the render
  tree — not a gap to close, a finalized specialization.

## Architecture
- **`app/lib/`** (Flutter/Dart):
  - `screens/`: `splash.dart`/`splash_gate.dart`, `library.dart` (vault file
    tree + recents), `reader.dart` (the document view), `native_doc_view.dart`,
    `outline_sheet.dart` (scrollspy bottom sheet), `search.dart`,
    `settings.dart`, `shell.dart` (tab bar / navigation host).
  - `render/`: `renderer.dart`, `engine_policy.dart` (native vs. Webview
    selection — native is always the default; a persisted per-document
    override is the only thing that changes it), `resolver.dart`
    (link/image resolution against the vault), `native_images.dart`,
    `native_palette.dart` (theme→plugin palette bridge), `link_policy.dart`
    (native link-tap decisions, including `LinkFragment` heading-anchor
    nav), `mermaid_bridge.dart` + `mermaid_diagram_view.dart` (native
    Mermaid-to-SVG rendering via a hidden offscreen webview), `scrollspy.dart`,
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
  for EVERY document, Mermaid included — `MermaidBridge` renders diagrams
  to SVG through a hidden offscreen webview, so mermaid no longer forces
  the whole document onto Webview. **Webview** (`webview_flutter`, the
  original `loadHtmlString` pipeline) is always available as a
  fallback/escape hatch — a `renderTree` failure of any kind falls back
  to it automatically, and it's switchable per-document by hand via the
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
- **v2.1**: native SVG image rasterization (`NativeImageResolver`).
- **v2.2 — engine sync (Cross-Repo Rendering Engine Synchronization
  Plan, Phase 2)**: `CHANGELOG.md` reconstructed from history; a new
  `.github/workflows/ci.yml` + `release.yml` CI/release-artifact
  pipeline (format/analyze/test + Android/iOS build verification, and
  packaged APK/AAB/unsigned-iOS-archive releases with checksums);
  consumed the library's CRLF code-fence fix, `FootnoteRef.DefID`/
  `Tree.FootnoteByIndex` primitive, and `mermaid-bridge.js` primitive
  (re-pinning `vendor/markdownviewer` to a raw commit pre-tag); proposed
  and got merged a small additive plugin API,
  `MdvRenderScope`/`MdvDocumentAdapter`/`MdvDocumentView.onFootnoteRefTap`
  (mirrors `onLinkTap`) — the typed model had no way to intercept a
  footnote-ref tap at all before this; dropped the auto-Webview-on-Mermaid
  rule and added native Mermaid rendering (`mermaid_bridge.dart` +
  `mermaid_diagram_view.dart`, an offscreen `webview_flutter` instance
  running `mermaid.js` + `mermaid-bridge.js`, SVG displayed via
  `flutter_svg`); added `#fragment`-only link nav resolved against
  `MdvHeading.anchorId` (`link_policy.dart`'s new `LinkFragment`
  decision); footnote-ref taps now jump to the trailing footnotes section
  (not yet the exact definition — see Known limitations); removed the
  CRLF syntax-highlighting limitation note (confirmed fixed upstream).

## Known limitations (v2, per README — organized by engine)
**Native engine only:** pure `#fragment` links jump to a matching HEADING
only (resolved via `MdvHeading.anchorId`; a non-heading fragment, e.g. a
custom raw-HTML `id`, is still inert); footnote-reference taps jump to
the trailing footnotes SECTION, not the exact definition
(`MdvDocumentAdapter` has no per-definition scroll target — every
definition renders inside one list item); reading-progress % is
block-weighted, not pixel-accurate; internal relative `.md` links push a
new Reader screen instead of replacing it (a real cross-engine back-stack
difference vs. Webview on iOS); a Mermaid diagram's rendered colors don't
follow a theme flip AFTER it has already rendered (every other native
block restyles in place; a diagram doesn't re-run the offscreen bridge
until the document reopens).
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
1. Re-pin `vendor/markdownviewer` to a proper `flutter-v*` tag once the
   library cuts one covering the CRLF fix / footnote linkage / mermaid
   bridge / `onFootnoteRefTap` commits this app currently pins to a raw
   commit for.
2. **Remaining native-engine gaps**: per-definition footnote scroll
   (needs a finer-grained scroll target than `MdvDocumentAdapter`'s one
   combined footnotes item — likely a plugin-side change, e.g. splitting
   the footnotes section into individually keyed/positioned items);
   `#fragment` nav for non-heading anchors; a Mermaid diagram re-rendering
   on a theme flip after first render; back-stack harmonization for
   relative `.md` links (native push vs. Webview replace).
3. Multi-vault support and PDF export are explicitly out of scope for the
   current version but flagged as desired follow-ups per the "Known
   limitations" list.
4. Now that `.github/workflows/ci.yml`/`release.yml` exist, keep them
   current as the toolchain/plugin evolve (Flutter version bumps, new
   release-artifact needs); revisit signing (currently debug-signed
   Android / unsigned iOS release artifacts) if real distribution is ever
   needed.
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
