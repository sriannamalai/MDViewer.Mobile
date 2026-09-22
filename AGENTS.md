# AGENTS.md — MDViewer.Mobile

Persistent project memory for agents. Update whenever architecture,
status, or roadmap materially changes.

## What this project is
A read-only Markdown viewer for iOS/Android, built with **Flutter**,
consuming the [MarkDownViewer](https://github.com/sriannamalai/markdownviewer)
Go library through its Flutter plugin (`flutter/mdviewer`, vendored here as
a git submodule at `vendor/markdownviewer` — pinned to the library's
`flutter-v0.11.0` tag; see README's "How the submodule is pinned";
underlying native binaries are v0.11.0). ~50 commits, app version `1.0.0+1`,
currently at "v2.3" per its own README (dual-engine reader, plus a batch
of open-issue fixes) — most mature of the two apps.

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

### Engine version sync checklist
Run this on every core library release (MarkDownViewer's own `AGENTS.md`
keeps the authoritative copy of this list — update both if it changes):
1. Check the library's `CHANGELOG.md` for the new `v<ver>`/`flutter-v<ver>`
   tags and what changed (new primitives, breaking changes, plugin API
   additions).
2. Bump the `vendor/markdownviewer` submodule to the new `flutter-v<ver>`
   tag (see README's "How the submodule is pinned").
3. Re-test dual-engine parity — native vs. Webview must render the same
   document consistently (`flutter test`, plus a manual per-doc engine
   switch check via the Reader's "Aa" sheet).
4. Update `scripts/bootstrap.sh` / `README.md` if either hardcodes the
   pinned tag or checksum references.
5. Update this file's "Finished so far" section with what actually shipped
   on the Mobile side, and confirm the sibling repos' `AGENTS.md` files
   were updated too (Desktop's pin + this checklist; the library's
   "Finished so far").
Current pinned version/path: submodule `flutter-v0.11.0` tag (native
binaries v0.11.0), native render tree default with Webview fallback.

## The sibling repos (the bigger picture)
- **`~/Developer/OpenSource/MarkDownViewer`** — the rendering engine. This
  app is the most advanced consumer of it: it's the first host to exercise
  the native **render tree** (`MdvDocumentView`/`MdvDocumentAdapter`)
  end-to-end, rather than just HTML-in-a-webview. Bugs found here often get
  fixed upstream first, then this repo bumps the `vendor/markdownviewer`
  submodule to a new `flutter-v<ver>` tag (see that repo's
  `CONTRIBUTING.md`'s Releasing section).
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
    nav, `LinkConfirmExternal` mailto:/tel:, and `LinkOpenSearch` wiki-link
    fallback), `wiki_link.dart` (wiki-link stem resolution against the
    vault, issue #10), `webview_fonts.dart` (embeds the app's bundled
    fonts into the Webview engine, issue #13), `mermaid_bridge.dart` +
    `mermaid_diagram_view.dart` (native Mermaid-to-SVG rendering via a
    hidden offscreen webview, theme-flip-aware since issue #7),
    `scrollspy.dart`, `codecopy.dart` (JS-channel bridge for the Webview
    engine's Copy button).
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
  `Tree.FootnoteByIndex` primitive, and `mermaid-bridge.js` primitive;
  proposed and got merged a small additive plugin API,
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
  CRLF syntax-highlighting limitation note (confirmed fixed upstream);
  re-pinned `vendor/markdownviewer` to the released `flutter-v0.11.0` tag
  once the library cut it (was a raw pre-tag commit pin during this pass).
- **v2.3 — open-issue batch (13 issues triaged, 10 fixed, 3 deferred)**:
  native Mermaid diagrams now re-render on a theme flip
  (`MermaidDiagramView` compares the ambient brightness against the
  theme its cached request was issued for); relative `.md` link
  navigation harmonized to PUSH on both engines (the Webview path used
  `pushReplacement` on iOS — now `pushReader`, matching native); a
  `mailto:`/`tel:` tap on either engine shows a brief "Open in
  Mail/Phone app?" confirmation sheet before handing off to
  `url_launcher` (`link_policy.dart`'s new `LinkConfirmExternal`);
  wiki-links (`[[Page Name]]`) now resolve against the vault by file
  stem via a new render-time resolver (`render/wiki_link.dart`) — a
  unique match navigates like a normal relative link, an ambiguous/
  unresolved one opens Search pre-filled with the raw text
  (`LinkOpenSearch`, `SearchScreen.initialQuery`); a native `#fragment`
  that doesn't resolve to a heading now shows a snackbar hint instead of
  a silent no-op; native reading progress is now PIXEL-weighted (each
  item's own on-screen extent, falling back to the average of measured
  extents) instead of counting every block as one equal unit; the
  Webview engine now embeds the app's bundled fonts as base64
  `@font-face` rules (`render/webview_fonts.dart`) instead of falling
  back to the system stack; an "Open with" document with unresolved
  relative refs shows a dismissible banner prompting "Choose folder"
  (auto-retrying the same filename from the newly-picked vault); the
  Share sheet gained a PDF export option (`printing` package's
  `Printing.convertHtml`, converting the same Webview-rendered HTML the
  HTML export already produces); `VaultState` now persists a LIST of
  folder vaults (`vault.grants` + `vault.activeGrantId`, migrated from
  the old single `vault.grant` key) with a Library switcher
  (add/switch/remove chips) instead of one folder at a time. Deferred:
  Android Webview relative-`.md` navigation (issue #12 — a `baseUrl` fix
  exists for Android but risks changing iOS's own-page-load navigation
  event too, unverifiable without a real device/simulator); exact-
  footnote-definition scroll and signed release artifacts (issues #3/
  #14 — both need something this repo alone can't provide: a plugin-
  side primitive, and signing secrets, respectively).

## Known limitations (v2.3, per README — organized by engine)
**Native engine only:** pure `#fragment` links jump to a matching HEADING
only (resolved via `MdvHeading.anchorId`; a non-heading fragment, e.g. a
custom raw-HTML `id`, now shows a snackbar hint instead of a silent
no-op, but still can't jump there directly); footnote-reference taps
jump to the trailing footnotes SECTION, not the exact definition
(`MdvDocumentAdapter` has no per-definition scroll target — every
definition renders inside one list item; needs a plugin-side change,
see issue #3).
**Both engines:** "Open with MDViewer" shows an actionable banner
("Choose folder") when a document has unresolved relative refs, but still
can't resolve them without that folder pick — iOS sandboxing rules out
granting parent-directory access automatically; read-only by design (no
editing/file management/sync).
**Webview engine only:** internal relative `.md` links only navigate on
iOS (Android's `loadHtmlString` has no base URL, so taps are a deliberate
no-op there — switch to Native to navigate on Android; issue #12 has a
candidate fix that needs on-device verification before it's safe to ship,
see its GitHub comment).

## Next items (proposed, mirrors the core library's own roadmap)
Since this app is explicitly the "native-render validation" testbed the
core library's roadmap calls for, its own next steps are largely the same
list, from this app's side:
1. **Remaining native-engine gaps**: per-definition footnote scroll
   (needs a finer-grained scroll target than `MdvDocumentAdapter`'s one
   combined footnotes item — a plugin-side change, e.g. splitting
   the footnotes section into individually keyed/positioned items —
   tracked as issue #3, deferred pending that); `#fragment` nav for
   non-heading anchors (has a snackbar fallback now, issue #4, but not
   a real jump — also needs a plugin-side primitive).
2. **Android Webview relative-`.md` navigation** (issue #12): a
   `baseUrl`-based fix is identified but needs a real device/simulator
   pass to confirm it doesn't change what iOS's WKWebView reports for
   its OWN page load (see the issue's comment for exactly what to
   verify) before it's safe to ship.
3. Now that `.github/workflows/ci.yml`/`release.yml` exist, keep them
   current as the toolchain/plugin evolve (Flutter version bumps, new
   release-artifact needs); revisit signing (currently debug-signed
   Android / unsigned iOS release artifacts, issue #14) once real
   signing secrets (keystore, provisioning profile) are available.
4. Keep the `vendor/markdownviewer` submodule pin current as the library
   ships new `flutter-v<ver>` tags — check the library's `CHANGELOG.md`
   for Flutter-relevant changes each time.
5. Multi-vault support (issue #9) shipped a reasonably-scoped version
   (a persisted list + Library switcher), but `VaultSource`/`VaultEntry`
   still key resolution by source alone, so a folder-vault entry only
   resolves while ITS vault is active — broadening that to make every
   vault simultaneously resolvable (a per-instance vault id threaded
   through `findByRelPath`/`resolveRelative`/`markdownRelPaths`) is a
   larger follow-up if it turns out to matter in practice.

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
