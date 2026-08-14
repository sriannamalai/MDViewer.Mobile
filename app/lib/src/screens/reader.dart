import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:mdviewer/mdviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../navigation.dart';
import '../render/codecopy.dart';
import '../render/engine_policy.dart';
import '../render/link_policy.dart';
import '../render/native_images.dart';
import '../render/renderer.dart';
import '../render/resolver.dart';
import '../render/scrollspy.dart';
import '../state/app_state.dart';
import '../state/doc_state.dart';
import '../state/vault_state.dart';
import '../tokens.dart';
import '../util/share_filename.dart';
import '../vault/vault_entry.dart';
import '../vault/vault_path.dart';
import '../vault/vault_source.dart';
import '../widgets/text_scale_stepper.dart';
import 'native_doc_view.dart';
import 'outline_sheet.dart';

/// The Reader — design/README.md §02: blurred header (back/filename+meta/
/// share), a 2px scroll-progress hairline, the rendered document, and a
/// blurred bottom bar (Outline pill, current section·%, an "Aa" text-size
/// control). As of v2 the chrome hosts one of TWO engines — only the
/// content widget swaps:
///
/// - **native** (the default): `DocRenderer.renderTree` → typed [MdvTree]
///   → [NativeDocView] ([MdvDocumentAdapter] over a positioned list).
///   Text scale and theme feed the adapter at BUILD time, so Aa steps and
///   theme flips restyle in place with no re-render and no scroll reset.
///   Built AT MOST ONCE per document, ever — cached on state; never
///   rebuilt on Aa/theme/engine switches.
/// - **webview** (v1's path, byte-for-byte unchanged): parse → render →
///   `loadHtmlString` with the injected scrollspy/code-copy scripts,
///   re-rendered on theme/text-scale changes. Auto-selected for mermaid
///   documents (`treeContainsMermaid`) until the offscreen-SVG
///   fast-follow.
///
/// Engine resolution (engine_policy.dart): the per-document persisted
/// override (`reader.engine.…`, the Aa sheet's Engine row) wins outright
/// — it even skips the detection `renderTree`; else mermaid → webview;
/// else native.
///
/// **Fallback posture:** a [DocRenderer.renderTree] failure of ANY kind
/// falls back to the webview engine — a tree the plugin can't build must
/// never brick the reader, and the webview engine always works. The
/// failure is remembered per document (no retry storms); the cached
/// verdict also serves engine switches.
///
/// The webview pipeline is otherwise as it always was: reads [entry]'s
/// bytes, parses them once (`renderer.dart`'s [DocRenderer]), pre-resolves
/// its relative images (`resolver.dart`'s [DocImages]) before the first
/// render (the plugin's HTML resolver callback is synchronous; the vault
/// read isn't — see resolver.dart's doc comment), injects the scrollspy
/// and code-copy scripts (`scrollspy.dart`, `codecopy.dart`), and
/// re-renders (preserving scroll position) whenever the effective theme or
/// text-scale step changes. On the native engine images resolve lazily and
/// async instead (`native_images.dart`) and there is no prefetch pass —
/// [DocImages] runs on demand the first time the webview engine or the
/// share export actually needs it (never per build).
///
/// The [WebViewController] and its JavaScript channels are created LAZILY,
/// only once the engine actually resolves to webview — a native document
/// must not create (or register channels on) a webview it never shows.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.entry,
    this.renderer,
    this.initialLine,
  });

  final VaultEntry entry;

  /// A source line (`[data-md-line="…"]`) to scroll to right after the
  /// first page load — the Search screen's "tap a result → Reader, jumped
  /// to the match" behavior (design/README.md §04) and the Outline sheet's
  /// analogous in-Reader jump both ultimately run the same
  /// `__mdvScrollToLine` script (`scrollspy.dart`), but this one fires
  /// automatically on load rather than from a user tap once already
  /// reading. Takes priority over restoring a persisted scroll position
  /// (`_prefsKey`) for this same single load — a search result should land
  /// on the match, not wherever the reader was last left off. Null (the
  /// Library/open-with/Outline-internal-link paths) falls back to that
  /// persisted-progress restore exactly as before this field existed.
  final int? initialLine;

  /// Overridable for tests: `Mdviewer.instance` only resolves its native
  /// library on a real device/simulator/emulator (see
  /// `renderer.dart`/`mdviewer_version.dart`'s doc comments), so a widget
  /// test that wants to exercise the *loaded* Reader (header meta, bottom
  /// bar section/%, scrollspy wiring) injects a fake [DocRenderer]
  /// subclass instead of hitting the real FFI call.
  final DocRenderer? renderer;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum _LoadStatus { loading, ready, error }

class _ReaderScreenState extends State<ReaderScreen> {
  static const double _headerButtonSize = 38;
  static const double _bottomBarContentHeight = 54;
  static const double _hairlineHeight = 2;

  late final DocRenderer _renderer = widget.renderer ?? DocRenderer();

  /// Created lazily by [_ensureController], the first time the engine
  /// actually resolves to webview (load, or a native→webview switch) —
  /// null for the whole lifetime of a document that only ever renders
  /// natively. Created at most once; an engine round-trip reuses it.
  WebViewController? _controller;

  _LoadStatus _status = _LoadStatus.loading;
  Object? _error;
  Map<String, dynamic>? _parsedDoc;

  /// The engine currently hosting the document (null until [_load]
  /// resolves it). Swapped live by [_setEngine].
  ReaderEngine? _engine;

  /// The document's typed render tree — built AT MOST ONCE per document
  /// by [_ensureTree] (never on Aa steps, theme flips, or engine
  /// switches). Null while unbuilt or when [renderTree] failed
  /// ([_treeAttempted] remembers the attempt either way).
  MdvTree? _tree;
  bool _treeAttempted = false;

  /// The native engine's scroll plumbing, one instance per native
  /// activation (created by [_setUpNativeScroll], disposed on
  /// native→webview switch and in [dispose]).
  NativeReaderScroll? _nativeScroll;

  /// The item index the native list first paints at — computed BEFORE
  /// paint from the engine-neutral line (restore / initialLine /
  /// switch handoff), so position restore lands as list construction.
  int _nativeInitialIndex = 0;

  /// The native engine's image resolver — ONE long-lived callback per
  /// document (the plugin memoizes on callback equality; an inline
  /// closure per build would refetch every image every rebuild — see
  /// native_images.dart's identity contract).
  MdvImageResolver? _nativeImageResolver;

  /// Whether [_images] holds this document's [DocImages.prefetch]
  /// result yet. The webview load path prefetches eagerly (its HTML
  /// resolver is synchronous); a native-engine document defers it until
  /// the webview engine or the share export first needs it — lazily at
  /// that moment, once, never per build.
  bool _imagesPrefetched = false;

  /// The images [_load] prefetched for this document, kept for the
  /// screen's lifetime so theme/text-scale re-renders reuse them. (Found
  /// on-device in Task 8's E2E: [_renderInto] used to default to
  /// [DocImages.empty] on re-render, so stepping Aa or toggling theme
  /// silently dropped every relative image from the re-rendered page.)
  DocImages _images = DocImages.empty;

  /// Set once, in [_load], the moment the document's [DocModel] is known.
  /// Its own listener (added right after construction) triggers a local
  /// `setState` on every scrollspy update, so the header meta/hairline/
  /// bottom bar redraw without needing an `InheritedWidget` for a value
  /// that never leaves this single screen in v1 (Task 6's outline sheet is
  /// the first consumer that would need it exposed further, and can wrap
  /// its own `ChangeNotifierProvider` around this same instance then).
  ReaderDocState? _docState;

  double? _pendingRestoreProgress;

  /// Set from [ReaderScreen.initialLine] in [initState] and consumed
  /// (cleared) the first time [_handlePageFinished] fires — a later
  /// re-render (theme/text-scale change) must NOT re-jump to the original
  /// search match, so this is a one-shot, unlike [_pendingRestoreProgress]
  /// (which [build]'s rerender branch deliberately re-arms every time).
  int? _pendingInitialLine;
  bool _rerendering = false;
  double _renderedScale = AppState.defaultTextScale;
  Brightness? _renderedBrightness;

  String get _prefsKey =>
      'reader.scroll.${widget.entry.source.name}:${widget.entry.relPath}';

  /// The engine-neutral top-line key (`reader.line.…`, engine_policy.dart)
  /// BOTH engines write, so switching engines keeps your place. The native
  /// engine restores from it; the webview keeps restoring by [_prefsKey]'s
  /// progress float exactly as before.
  String get _linePrefsKey =>
      lineKey(widget.entry.source, widget.entry.relPath);

  /// The per-document engine override key (`reader.engine.…`,
  /// engine_policy.dart) — absent means auto-detect.
  String get _enginePrefsKey =>
      engineKey(widget.entry.source, widget.entry.relPath);

  @override
  void initState() {
    super.initState();
    _pendingInitialLine = widget.initialLine;
    unawaited(_load());
  }

  /// Creates (once) and returns the webview controller + channels —
  /// byte-for-byte the configuration v1 built eagerly in [initState],
  /// now deferred until the engine actually resolves to webview so a
  /// native document never pays for (or registers) a webview.
  WebViewController _ensureController() {
    final existing = _controller;
    if (existing != null) return existing;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        scrollSpyChannelName,
        onMessageReceived: _handleScrollSpyMessage,
      )
      ..addJavaScriptChannel(
        codeCopyChannelName,
        onMessageReceived: _handleCodeCopyMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageFinished: _handlePageFinished,
        ),
      );
    _controller = controller;
    return controller;
  }

  @override
  void dispose() {
    _nativeScroll?.dispose();
    _docState?.removeListener(_handleDocStateChanged);
    _docState?.dispose();
    super.dispose();
  }

  void _handleDocStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final vault = context.read<VaultState>();
    try {
      final bytes = await vault.readDoc(widget.entry);
      final markdown = utf8.decode(bytes, allowMalformed: true);
      final parsed = _renderer.parse(markdown);
      final model = DocModel.analyze(parsed);

      final prefs = await SharedPreferences.getInstance();

      // Engine resolution (engine_policy.dart's precedence): a persisted
      // per-document override wins outright — it even skips the
      // detection renderTree (an override never re-detects). Otherwise
      // the tree is built once here and walked for mermaid; a renderTree
      // failure of any kind resolves to webview (see the class doc's
      // fallback posture).
      final override = ReaderEngine.decode(prefs.getString(_enginePrefsKey));
      ReaderEngine engine;
      if (override != null) {
        engine = override;
      } else {
        final tree = _ensureTree(parsed);
        engine = tree == null
            ? ReaderEngine.webview
            : resolveEngine(
                persistedOverride: null,
                hasMermaid: treeContainsMermaid(tree),
              );
      }
      // The override=native case still needs the tree (detection never
      // ran); a failed build falls back to webview here too.
      if (engine == ReaderEngine.native && _ensureTree(parsed) == null) {
        engine = ReaderEngine.webview;
      }

      final docState = ReaderDocState(model: model);

      if (engine == ReaderEngine.native) {
        // NO image prefetch on the native path: the adapter's resolver
        // is async, so images resolve lazily on demand — one long-lived
        // callback per document (identity contract, native_images.dart).
        _nativeImageResolver = NativeImageResolver(
          resolveBytes: (relPath) =>
              vault.resolveRelative(widget.entry, relPath),
        ).call;
        // A search-result initialLine beats the persisted line, same
        // one-shot priority as the webview path — consumed here (the
        // native list paints there; a later engine switch must not
        // re-jump to it).
        final initialLine = _pendingInitialLine;
        _pendingInitialLine = null;
        _setUpNativeScroll(
          _tree!,
          docState,
          initialLine: initialLine,
          persistedLine: NativeReaderScroll.persistedLine(prefs, _linePrefsKey),
        );
      } else {
        final images = await DocImages.prefetch(
          parsed,
          (relPath) => vault.resolveRelative(widget.entry, relPath),
        );
        _images = images;
        _imagesPrefetched = true;
        _pendingRestoreProgress = prefs.getDouble(_prefsKey);
      }

      if (!mounted) return;
      docState.addListener(_handleDocStateChanged);
      setState(() {
        _parsedDoc = parsed;
        _docState = docState;
        _engine = engine;
        _status = _LoadStatus.ready;
      });
      if (engine == ReaderEngine.webview) {
        await _renderInto();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _LoadStatus.error;
        _error = error;
      });
    }
  }

  /// Builds the document's [MdvTree] AT MOST ONCE, ever: the first call
  /// attempts [DocRenderer.renderTree] and caches the outcome — tree or
  /// failure — and every later call (Aa steps and theme flips never get
  /// here; engine switches do) returns that cached verdict. Null means
  /// the build failed: the caller falls back to the webview engine (the
  /// class doc's fallback posture — this is also exactly what keeps a
  /// host without the FFI library on the always-working webview path).
  MdvTree? _ensureTree(Object doc) {
    if (_treeAttempted) return _tree;
    _treeAttempted = true;
    try {
      _tree = _renderer.renderTree(doc);
    } catch (_) {
      _tree = null;
    }
    return _tree;
  }

  /// Creates the native scroll plumbing for one native activation and
  /// precomputes the list's first-paint index from the engine-neutral
  /// line ([NativeReaderScroll.initialScrollIndex]'s priority:
  /// [initialLine] beats [persistedLine]; no line → top).
  void _setUpNativeScroll(
    MdvTree tree,
    ReaderDocState docState, {
    int? initialLine,
    int? persistedLine,
  }) {
    final scroll = NativeReaderScroll(
      tree: tree,
      docState: docState,
      progressKey: _prefsKey,
      lineKey: _linePrefsKey,
    );
    _nativeInitialIndex = scroll.initialScrollIndex(
      initialLine: initialLine,
      persistedLine: persistedLine,
    );
    _nativeScroll = scroll;
  }

  Future<void> _renderInto() async {
    final doc = _parsedDoc;
    if (doc == null) return;
    final appState = context.read<AppState>();
    final brightness = Theme.of(context).brightness;
    final scale = appState.textScale;

    final html = _renderer.render(
      doc,
      brightness: brightness,
      textScale: scale,
      resolver: _images.toResolver(),
    );
    _renderedScale = scale;
    _renderedBrightness = brightness;
    // Both injectors use the same lastIndexOf('</body>') splice, and
    // neither script contains a '</body>' literal, so order only decides
    // which script sits first before the real closing tag — semantically
    // independent either way.
    await _ensureController().loadHtmlString(
      injectCodeCopy(injectScrollSpy(html)),
    );
  }

  /// Live engine swap (the Aa sheet's Engine row), keeping the reading
  /// position via the engine-neutral line — [ReaderDocState.activeLine],
  /// the same value both engines persist. Persists the per-document
  /// override first: the user's choice is absolute in both directions
  /// (engine_policy.dart's precedence).
  Future<void> _setEngine(ReaderEngine engine) async {
    if (_engine == engine || _status != _LoadStatus.ready) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_enginePrefsKey, engine.wire);
    if (!mounted) return;
    if (engine == ReaderEngine.native) {
      await _activateNative();
    } else {
      await _activateWebview();
    }
  }

  /// webview → native: build (or reuse — [_ensureTree] caches, so
  /// renderTree still runs at most once per document across any number
  /// of switches) the tree, map the current line to its block index
  /// BEFORE the native list's first paint, and swap the content widget.
  /// If the tree can't be built the reader STAYS on webview (fallback
  /// posture) — the override is persisted regardless, and the next open
  /// resolves it the same way.
  Future<void> _activateNative() async {
    final doc = _parsedDoc;
    final docState = _docState;
    if (doc == null || docState == null) return;
    final tree = _ensureTree(doc);
    if (tree == null) return;
    final vault = context.read<VaultState>();
    _nativeImageResolver ??= NativeImageResolver(
      resolveBytes: (relPath) => vault.resolveRelative(widget.entry, relPath),
    ).call;
    final line = docState.activeLine;
    _setUpNativeScroll(
      tree,
      docState,
      initialLine: line > 0 ? line : null,
      persistedLine: null,
    );
    setState(() => _engine = ReaderEngine.native);
  }

  /// native → webview: dispose the native scroll plumbing (flushing its
  /// pending position write), create the lazy controller NOW, and
  /// restore the position by re-arming the existing one-shot
  /// [_pendingInitialLine] machinery — [_handlePageFinished] consumes it
  /// exactly once after the load, so the jump can't double-fire and a
  /// later Aa/theme re-render is back on the normal progress-restore
  /// path. Prefetches [DocImages] first if this document never ran it
  /// (native-engine docs defer it — see [_imagesPrefetched]).
  Future<void> _activateWebview() async {
    final docState = _docState;
    _nativeScroll?.dispose();
    _nativeScroll = null;
    final line = docState?.activeLine ?? 0;
    _pendingInitialLine = line > 0 ? line : null;
    _pendingRestoreProgress = null;
    await _prefetchImagesOnce();
    if (!mounted) return;
    _ensureController();
    setState(() => _engine = ReaderEngine.webview);
    await _renderInto();
  }

  /// Runs this document's [DocImages.prefetch] if it hasn't run yet —
  /// the lazy half of the split documented on [_imagesPrefetched]
  /// (webview loads prefetch eagerly; native-engine docs land here from
  /// [_share] or a native→webview switch). Never runs twice, never per
  /// build.
  Future<void> _prefetchImagesOnce() async {
    if (_imagesPrefetched) return;
    final doc = _parsedDoc;
    if (doc == null) return;
    final vault = context.read<VaultState>();
    _images = await DocImages.prefetch(
      doc,
      (relPath) => vault.resolveRelative(widget.entry, relPath),
    );
    _imagesPrefetched = true;
  }

  void _handleScrollSpyMessage(JavaScriptMessage message) {
    final payload = ScrollSpyPayload.tryParse(message.message);
    if (payload == null) return;
    _docState?.applyScrollSpy(payload);
    unawaited(_persistScroll(payload.progress));
    // Engine-neutral line persistence — the ONE additive webview-path
    // change the v2 train makes: the payload already carries the line,
    // so it rides the existing per-message cadence (the float write
    // above is byte-for-byte unchanged). The native engine restores by
    // this line (NativeReaderScroll), so a doc read under the webview
    // engine reopens in place after an engine switch.
    unawaited(_persistLine(payload.line));
  }

  /// The code-block Copy button's clipboard write. The message body IS the
  /// code text (raw `pre.innerText`, not JSON — see codecopy.dart): a
  /// `loadHtmlString` page has no `navigator.clipboard` (non-secure
  /// origin), so the injected bridge posts the text here and the host
  /// performs the write the page itself can't.
  void _handleCodeCopyMessage(JavaScriptMessage message) {
    unawaited(Clipboard.setData(ClipboardData(text: message.message)));
  }

  Future<void> _persistScroll(double progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, progress);
  }

  Future<void> _persistLine(int line) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_linePrefsKey, line);
  }

  void _handlePageFinished(String url) {
    // Only ever invoked by the webview's own NavigationDelegate, so the
    // lazy controller necessarily exists by now.
    final controller = _controller;
    if (controller == null) return;
    final line = _pendingInitialLine;
    if (line != null) {
      _pendingInitialLine = null;
      // A search-result jump wins over restoring the persisted scroll
      // position for this load — see ReaderScreen.initialLine's doc
      // comment. Drop any pending restore too, so a later re-render
      // doesn't undo the jump by restoring the *old* progress instead of
      // whatever scrollspy reports once the jump lands.
      _pendingRestoreProgress = null;
      unawaited(controller.runJavaScript(scrollToLineScript(line)));
      return;
    }

    final restore = _pendingRestoreProgress;
    if (restore != null) {
      _pendingRestoreProgress = null;
      unawaited(controller.runJavaScript(scrollToProgressScript(restore)));
    }
  }

  FutureOr<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      unawaited(_openExternal(uri));
      return NavigationDecision.prevent;
    }
    if (uri.scheme.isEmpty) {
      unawaited(_openInternalRelative(request.url));
      return NavigationDecision.prevent;
    }
    // A data: request reaching the delegate can only be a tapped link
    // (e.g. `[open](data:text/html;base64,...)`), never the rendered
    // document's own load: Android's WebView doesn't route API-initiated
    // loads through shouldOverrideUrlLoading at all, and iOS WKWebView
    // surfaces loadHtmlString's own load as about:blank. Allowing it let
    // such a link replace the document with link-authored HTML inside the
    // reader (on iOS) — decline instead.
    if (uri.scheme == 'data') return NavigationDecision.prevent;
    // iOS WKWebView routes loadHtmlString's own load through the delegate
    // as exactly `about:blank` — allow only that, only there. Any other
    // about:* URL (e.g. a doc link like `[x](about:config)`) is a tapped
    // link and falls through to the decline below. Android's WebView never
    // sends API-initiated loads through shouldOverrideUrlLoading, so an
    // about:* request there can only be a tapped relative link that
    // Chromium collapsed against the null base URL — allowing it navigated
    // the WebView to a literal blank page (found on-device in Task 8's
    // E2E).
    if (request.url == 'about:blank' &&
        defaultTargetPlatform != TargetPlatform.android) {
      return NavigationDecision.navigate;
    }
    // Everything else — mailto:, tel:, file:, data:, about: on Android and
    // non-blank about:* on iOS, unknown schemes — is an explicit decline
    // now, not a fall-through navigate (which could replace the document
    // with a blank/error/attacker-authored page). v1 scope: only web links
    // (external) and vault-relative .md links (internal) actually go
    // somewhere.
    return NavigationDecision.prevent;
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort: no system browser available / launch declined. No UI
      // feedback per the task brief's scope — a no-op is the safe default.
    }
  }

  /// Internal relative `.md` link handling (design/README.md §Interactions):
  /// looked up against [VaultState] and, if found, replaces this Reader
  /// (`pushReplacement`) with a new one for the resolved entry. Anything
  /// that isn't a resolvable `.md`/`.markdown` target is a no-op — the
  /// brief's documented v1 behavior, not a bug (wiki-links and links to
  /// files outside the vault have nowhere to navigate to).
  Future<void> _openInternalRelative(String href) async {
    final target = href.split('#').first.split('?').first;
    if (target.isEmpty) return;
    final lower = target.toLowerCase();
    if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) return;

    final resolved = VaultPath.resolve(widget.entry.relPath, target);
    if (resolved == null || !mounted) return;

    final vault = context.read<VaultState>();
    final found = vault.findByRelPath(widget.entry.source, resolved);
    if (found == null || !mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(entry: found)),
    );
  }

  /// The native engine's link taps ([NativeDocView.onLinkTap]), routed
  /// through the shared pure decision table (`link_policy.dart`) so the
  /// two engines can never drift:
  ///
  /// - [blocked] → defensive no-op (the plugin renders blocked links
  ///   inert with no tap affordance, so this is never called for one in
  ///   practice — but a policy change upstream must not turn into a
  ///   navigation here).
  /// - [LinkExternal] → the same [_openExternal] the webview path uses.
  /// - [LinkInternalMd] → resolve against this entry's directory and
  ///   push a Reader on BOTH platforms — natively retiring the v1
  ///   webview path's Android internal-nav no-op.
  /// - [LinkDecline] → no-op (mailto/tel/data/about/unknown, non-md
  ///   targets, and pure `#fragment` anchors — the latter a documented
  ///   v2 native limitation; the webview engine handles them in-page).
  void _handleNativeLinkTap(String url, bool blocked, String? source) {
    if (blocked) return;
    switch (decideLinkTap(url, platform: defaultTargetPlatform)) {
      case LinkExternal(:final uri):
        unawaited(_openExternal(uri));
      case LinkInternalMd(:final target):
        unawaited(_openInternalMd(target));
      case LinkDecline():
        break;
    }
  }

  /// The native half of internal `.md` navigation: same
  /// [VaultPath.resolve] + [VaultState.findByRelPath] lookup the webview
  /// path performs, but the destination is PUSHED ([pushReader]) rather
  /// than replacing this Reader — back returns to the linking document.
  /// Unresolvable targets (absolute paths, vault escapes, files not in
  /// the vault) are a no-op, matching the webview path's documented
  /// behavior.
  Future<void> _openInternalMd(String target) async {
    final resolved = VaultPath.resolve(widget.entry.relPath, target);
    if (resolved == null || !mounted) return;

    final vault = context.read<VaultState>();
    final found = vault.findByRelPath(widget.entry.source, resolved);
    if (found == null || !mounted) return;

    await pushReader(context, found);
  }

  Future<void> _share() async {
    final doc = _parsedDoc;
    if (doc == null || !mounted) return;
    try {
      // A native-engine document never prefetched its images (the
      // adapter resolves them lazily); the share export's synchronous
      // HTML resolver needs them, so run the prefetch NOW, once —
      // cached for later shares and any engine switch. A no-op on
      // webview-engine docs (prefetched at load).
      await _prefetchImagesOnce();
      if (!mounted) return;
      final brightness = Theme.of(context).brightness;
      final html = _renderer.render(
        doc,
        brightness: brightness,
        textScale: context.read<AppState>().textScale,
        // Same prefetched images the on-screen render embeds: without the
        // resolver the exported "self-contained" HTML would silently lose
        // every relative image (same Task 8 E2E finding as _renderInto).
        resolver: _images.toResolver(),
      );
      final dir = await getTemporaryDirectory();
      final filename = ShareFilename.forEntryName(widget.entry.name);
      final file = File('${dir.path}/$filename');
      await file.writeAsString(html);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/html', name: filename)],
          subject: widget.entry.name,
        ),
      );
    } catch (_) {
      // Best-effort share; no UI feedback for a failed share sheet per the
      // brief's scope (same "no toasts" posture other screens follow).
    }
  }

  /// The Aa bottom sheet: the text-size stepper plus — once the
  /// document is loaded — the per-document Engine row (the reader's one
  /// menu surface; the header carries only back/share, so per the
  /// spec's "chrome identical across engines" rule the switch lives
  /// here. Placement flagged for Sri at final review as the spec's
  /// "existing overflow/menu area").
  void _openTextScaleSheet() {
    final tokens = AppTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppGeometry.sheetRadius),
        ),
      ),
      // StatefulBuilder so the Engine row re-highlights after a switch
      // completes — the sheet is its own route, so the Reader's
      // setState alone would not rebuild it.
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: tokens.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const TextScaleStepper(),
                if (_engine != null) ...[
                  const SizedBox(height: 24),
                  _EngineSelector(
                    engine: _engine!,
                    onSelect: (engine) async {
                      await _setEngine(engine);
                      if (sheetContext.mounted) setSheetState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Presents the Outline sheet (design/README.md §03) over this Reader —
  /// a no-op while the document hasn't finished loading yet (no
  /// [ReaderDocState] to show). Wires its tap-a-heading callback straight
  /// to the same `__mdvScrollToLine` script the search screen (Task 7) will
  /// also use — the sheet dismisses itself right after invoking this.
  void _openOutlineSheet() {
    final docState = _docState;
    if (docState == null) return;
    OutlineSheet.show(context, docState: docState, onTapHeading: _jumpToLine);
  }

  /// The Reader's engine routing seam for a user-initiated jump-to-line
  /// (outline tap): the native engine goes to
  /// [NativeReaderScroll.scrollToLine] (blockIndexForLine → an animated
  /// `scrollTo`); the webview engine runs the injected
  /// `__mdvScrollToLine` script — VERBATIM v1 behavior. The
  /// [OutlineSheet] itself is engine-agnostic and unchanged.
  void _jumpToLine(int line) {
    final scroll = _nativeScroll;
    if (_engine == ReaderEngine.native && scroll != null) {
      unawaited(scroll.scrollToLine(line));
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.runJavaScript(scrollToLineScript(line)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appState = context.watch<AppState>();
    final brightness = Theme.of(context).brightness;

    // The re-render-on-Aa/theme machinery is a WEBVIEW-ENGINE concern
    // only: the native engine feeds text scale and palette to the
    // adapter at build time, so a rebuild IS the restyle — re-rendering
    // there would rebuild a document that never went stale.
    if (_status == _LoadStatus.ready &&
        _engine == ReaderEngine.webview &&
        (_renderedScale != appState.textScale ||
            _renderedBrightness != brightness) &&
        !_rerendering) {
      _rerendering = true;
      final restoreProgress = _docState?.progress;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _rerendering = false;
        if (!mounted) return;
        _pendingRestoreProgress = restoreProgress;
        await _renderInto();
      });
    }

    final vault = context.watch<VaultState>();
    final docState = _docState;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _ReaderHeader(
              entry: widget.entry,
              buttonSize: _headerButtonSize,
              meta: docState == null
                  ? _vaultLabel(widget.entry.source, vault)
                  : '${_vaultLabel(widget.entry.source, vault)} · '
                        '${docState.model.readMinutes} min',
              onBack: () => Navigator.of(context).maybePop(),
              onShare: _share,
            ),
            _ProgressHairline(
              height: _hairlineHeight,
              progress: docState?.progress ?? 0,
            ),
            Expanded(child: _buildContent(tokens)),
            _BottomBar(
              contentHeight: _bottomBarContentHeight,
              sectionLabel: docState?.activeHeading?.text ?? widget.entry.name,
              percent: ((docState?.progress ?? 0).clamp(0.0, 1.0) * 100)
                  .round(),
              onOutlineTap: _openOutlineSheet,
              onAaTap: _openTextScaleSheet,
            ),
          ],
        ),
      ),
    );
  }

  static String _vaultLabel(VaultSource source, VaultState vault) {
    switch (source) {
      case VaultSource.sample:
        return 'Samples';
      case VaultSource.folder:
        return vault.vaultName ?? 'Vault';
      case VaultSource.openedFile:
        return 'Opened file';
    }
  }

  Widget _buildContent(AppTokens tokens) {
    switch (_status) {
      case _LoadStatus.loading:
        return Center(child: CircularProgressIndicator(color: tokens.accent));
      case _LoadStatus.error:
        return _ReaderError(error: _error, tokens: tokens);
      case _LoadStatus.ready:
        final scroll = _nativeScroll;
        final tree = _tree;
        if (_engine == ReaderEngine.native && scroll != null && tree != null) {
          return NativeDocView(
            tree: tree,
            itemScrollController: scroll.itemScrollController,
            itemPositionsListener: scroll.itemPositionsListener,
            initialScrollIndex: _nativeInitialIndex,
            onLinkTap: _handleNativeLinkTap,
            imageProvider: _nativeImageResolver,
          );
        }
        return WebViewWidget(controller: _ensureController());
    }
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.entry,
    required this.buttonSize,
    required this.meta,
    required this.onBack,
    required this.onShare,
  });

  final VaultEntry entry;
  final double buttonSize;
  final String meta;
  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppGeometry.barBlurSigma,
          sigmaY: AppGeometry.barBlurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.bg.withValues(
              alpha: AppGeometry.barSurfaceOpacityMax,
            ),
            border: Border(bottom: BorderSide(color: tokens.line2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                _HeaderButton(
                  size: buttonSize,
                  glyph: '‹',
                  glyphSize: AppTypeScale.readerBackGlyphSize,
                  color: tokens.accent,
                  semanticLabel: 'Back',
                  onTap: onBack,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppFonts.ibmPlexSans,
                          fontSize: AppTypeScale.readerFilenameSize,
                          fontWeight: AppTypeScale.readerFilenameWeight,
                          color: tokens.text,
                        ),
                      ),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.jetBrainsMono,
                          fontSize: AppTypeScale.uiMetaSizeMin,
                          color: tokens.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                _HeaderButton(
                  size: buttonSize,
                  glyph: '⇪',
                  glyphSize: AppTypeScale.readerShareGlyphSize,
                  color: tokens.text2,
                  semanticLabel: 'Share',
                  onTap: onShare,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.size,
    required this.glyph,
    required this.glyphSize,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

  final double size;
  final String glyph;
  final double glyphSize;
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: Center(
              child: Text(
                glyph,
                style: TextStyle(fontSize: glyphSize, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressHairline extends StatelessWidget {
  const _ProgressHairline({required this.height, required this.progress});

  final double height;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return SizedBox(
      height: height,
      child: ColoredBox(
        color: tokens.line2,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            // heightFactor is required here: Align hands the fill loose
            // height constraints, and without it the accent ColoredBox
            // sizes to zero height — a track with an invisible fill
            // (caught on-device in Task 8's E2E; the widget test now pins
            // the painted size too).
            heightFactor: 1,
            child: ColoredBox(color: tokens.accent),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.contentHeight,
    required this.sectionLabel,
    required this.percent,
    required this.onOutlineTap,
    required this.onAaTap,
  });

  final double contentHeight;
  final String sectionLabel;
  final int percent;
  final VoidCallback onOutlineTap;
  final VoidCallback onAaTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final metaStyle = TextStyle(
      fontFamily: AppFonts.jetBrainsMono,
      fontSize: AppTypeScale.readerSectionSize,
      color: tokens.text3,
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppGeometry.barBlurSigma,
          sigmaY: AppGeometry.barBlurSigma,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.panel.withValues(
              alpha: AppGeometry.barSurfaceOpacityMax,
            ),
            border: Border(top: BorderSide(color: tokens.line)),
          ),
          padding: EdgeInsets.fromLTRB(
            10,
            8,
            10,
            (bottomInset > 0 ? bottomInset : 0) + 8,
          ),
          child: SizedBox(
            height: contentHeight,
            child: Row(
              children: [
                _OutlinePill(onTap: onOutlineTap),
                const Spacer(),
                // Two Texts, not one: only the section label may ellipsize.
                // A single '$sectionLabel · $percent%' Text with tail
                // ellipsis truncated the percent off entirely under a long
                // section heading (found on-device) — the design shows the
                // percent always visible ("Features · 34%").
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          sectionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ),
                      Text(' · $percent%', maxLines: 1, style: metaStyle),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _AaButton(onTap: onAaTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      height: 40,
      child: Material(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(AppGeometry.pillRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppGeometry.pillRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '☰',
                  style: TextStyle(
                    fontSize: AppTypeScale.readerOutlineGlyphSize,
                    color: tokens.text,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Outline',
                  style: TextStyle(
                    fontFamily: AppFonts.ibmPlexSans,
                    fontSize: AppTypeScale.readerOutlineTextSize,
                    fontWeight: AppTypeScale.readerOutlineTextWeight,
                    color: tokens.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AaButton extends StatelessWidget {
  const _AaButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: tokens.panel2,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: 'Text size',
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  fontFamily: AppFonts.ibmPlexSans,
                  fontSize: AppTypeScale.readerAaGlyphSize,
                  color: tokens.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Aa sheet's "Engine" row — a tokens-styled segmented
/// Native / Web view selector (same segment styling as Settings'
/// theme-mode selector) driving the Reader's per-document engine
/// override. [engine] is the engine currently hosting the document;
/// selecting the other one persists `reader.engine.…` and live-swaps,
/// keeping the reading position by line.
class _EngineSelector extends StatelessWidget {
  const _EngineSelector({required this.engine, required this.onSelect});

  final ReaderEngine engine;
  final void Function(ReaderEngine engine) onSelect;

  static String _label(ReaderEngine engine) {
    switch (engine) {
      case ReaderEngine.native:
        return 'Native';
      case ReaderEngine.webview:
        return 'Web view';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ENGINE',
          style: TextStyle(
            fontFamily: AppFonts.ibmPlexSans,
            fontSize: AppTypeScale.uiLabelSize,
            fontWeight: AppTypeScale.uiLabelWeight,
            letterSpacing: AppTypeScale.uiLabelLetterSpacing,
            color: tokens.text3,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: ReaderEngine.values.map((candidate) {
            final active = candidate == engine;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Material(
                  color: active ? tokens.accentSoft : tokens.panel2,
                  borderRadius: BorderRadius.circular(
                    AppGeometry.radiusButtonMax,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      AppGeometry.radiusButtonMax,
                    ),
                    onTap: () => onSelect(candidate),
                    child: Container(
                      height: AppGeometry.minTapTarget,
                      alignment: Alignment.center,
                      child: Text(
                        _label(candidate),
                        style: TextStyle(
                          fontFamily: AppFonts.ibmPlexSans,
                          fontSize: AppTypeScale.uiTextSize,
                          fontWeight: active
                              ? FontWeight.w600
                              : AppTypeScale.uiTextWeightMin,
                          color: active ? tokens.accent : tokens.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// The native engine's Reader-side scroll plumbing — ONE instance per
/// document, created alongside its [MdvTree] (Task 5's engine
/// integration is the consumer; this class is the whole scroll contract
/// it wires up).
///
/// Owns the [ItemScrollController]/[ItemPositionsListener] pair the
/// Reader hands to `NativeDocView`, plus everything hanging off item
/// positions:
///
/// - **Initial position** — [initialScrollIndex] maps a source line to
///   its containing block's index BEFORE first paint (a one-shot
///   [ReaderScreen.initialLine] beats the persisted line, mirroring the
///   webview's priority; [persistedLine] reads the `reader.line.…` key
///   defensively). The index feeds `NativeDocView.initialScrollIndex`,
///   so restore lands as list construction — no post-frame jump flash.
/// - **Outline taps** — [scrollToLine]: `blockIndexForLine` → a short
///   animated `scrollTo` (the native half of the Reader's `_jumpToLine`
///   engine seam).
/// - **Scrollspy** — the positions listener finds the topmost visible
///   item (MIN index with `itemTrailingEdge > 0`, matching the
///   webview's reading-offset spirit — a `leadingEdge >= 0` rule would
///   mispick under the list's 22px top padding), maps it through
///   `startLineForIndex` (null — the trailing footnotes item — keeps
///   the last line), and applies [ReaderDocState.applyScrollSpy] — the
///   SAME payload type and state object the webview path feeds, reused
///   verbatim, so hairline/section·%/outline-active-row light up
///   identically on both engines.
/// - **Progress** — `(topmostIndex + consumedFractionOfIt) / itemCount`,
///   clamped to 0..1, where the consumed fraction is how much of the
///   topmost item has scrolled above the viewport top. A BLOCK-WEIGHTED
///   approximation by design (every block counts equally regardless of
///   height): 0 exactly at the top, but mid-document values weigh
///   blocks, not pixels. At the document bottom the value SNAPS to
///   exactly 1.0: whenever the LAST item's trailing edge is on screen
///   (`itemTrailingEdge <= 1`) the document end is fully visible —
///   without the snap the block-weighted value only approaches
///   `(n-1+ε)/n` when the tail fits inside the viewport, and the
///   hairline/percent would never report the exact 1.0/100% the
///   webview engine reports at its scroll end. The snap requires the
///   document to be SCROLLABLE: when both ends are on screen at once
///   (item 0's leading edge at/below the viewport top AND the last
///   item's trailing edge at/above its bottom) the list never moves and
///   the webview reports 0 there — scrollY never leaves 0 — so a
///   fits-in-the-viewport document keeps its block-weighted value (0 at
///   rest) instead of opening at 100%.
/// - **Persistence** — throttled to at most one write per [throttle]
///   (default 500ms), trailing-edge with the LATEST value; [dispose]
///   flushes the pending value (a pop/kill right after scrolling must
///   not lose the position) and cancels the timer. Each write persists
///   BOTH the progress float (`reader.scroll.…`, the webview's restore
///   key) and the top line (`reader.line.…`) — engine-neutral, so
///   switching engines keeps your place.
///
/// [dispose] must be called when the document is torn down.
class NativeReaderScroll {
  NativeReaderScroll({
    required MdvTree tree,
    required this._docState,
    required this._progressKey,
    required this._lineKey,
    this.throttle = const Duration(milliseconds: 500),
    Future<void> Function(double progress, int line)? persist,
    ItemPositionsListener? positionsListener,
  }) : _adapter = MdvDocumentAdapter(tree),
       _persistOverride = persist,
       itemPositionsListener =
           positionsListener ?? ItemPositionsListener.create() {
    itemPositionsListener.itemPositions.addListener(_handlePositions);
  }

  /// Mapping-only adapter over the document's tree: [MdvDocumentAdapter.
  /// blockIndexForLine]/[MdvDocumentAdapter.startLineForIndex]/
  /// [MdvDocumentAdapter.itemCount] depend ONLY on the tree (spans), so
  /// this instance never builds an item and needs no styling parameters —
  /// `NativeDocView` constructs its own per-build adapter for rendering.
  final MdvDocumentAdapter _adapter;

  final ReaderDocState _docState;
  final String _progressKey;
  final String _lineKey;

  /// Minimum spacing between persistence writes (test seam; production
  /// uses the 500ms default).
  final Duration throttle;

  /// Test seam: replaces the SharedPreferences dual-key write. Null (the
  /// Reader) writes [_progressKey] + [_lineKey].
  final Future<void> Function(double progress, int line)? _persistOverride;

  /// Scroll control for the hosted list (outline jump; the initial
  /// position rides `initialScrollIndex` instead — never a post-frame
  /// jump).
  final ItemScrollController itemScrollController = ItemScrollController();

  /// Position stream for the hosted list. Injectable for tests (driven
  /// positions); the Reader uses the real one.
  final ItemPositionsListener itemPositionsListener;

  Timer? _throttleTimer;
  double? _pendingProgress;
  int? _pendingLine;

  /// Reads the persisted engine-neutral line under [key] from [prefs]:
  /// null when absent or not an int. Legacy installs carry ONLY the
  /// `reader.scroll.…` float — that float must never be misread as a
  /// line (this reads the line key alone), and a corrupt value under
  /// the line key degrades to null (top start), never a throw.
  static int? persistedLine(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    return raw is int ? raw : null;
  }

  /// The list index the document should FIRST paint at: [initialLine]
  /// (the one-shot search-result jump) beats [persistedLine] (the
  /// restore), matching the webview path's priority; whichever wins is
  /// mapped through `blockIndexForLine` (nearest preceding block). No
  /// line, or a line no spanned block precedes (including a spanless
  /// tree), → 0: top start.
  int initialScrollIndex({
    required int? initialLine,
    required int? persistedLine,
  }) {
    final line = initialLine ?? persistedLine;
    if (line == null) return 0;
    return _adapter.blockIndexForLine(line) ?? 0;
  }

  /// User-initiated jump (outline tap): the block containing [line],
  /// via a short animated scroll. No-ops when the line maps to no block
  /// (see [initialScrollIndex]) or the controller isn't attached yet.
  Future<void> scrollToLine(int line) async {
    final index = _adapter.blockIndexForLine(line);
    if (index == null || !itemScrollController.isAttached) return;
    await itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.ease,
    );
  }

  void _handlePositions() {
    final positions = itemPositionsListener.itemPositions.value;
    // Pre-layout (or between-list) frames report no positions: keep the
    // current state rather than snapping progress/line to zero.
    if (positions.isEmpty) return;
    final itemCount = _adapter.itemCount;
    if (itemCount == 0) return;

    ItemPosition? topmost;
    for (final position in positions) {
      // trailingEdge <= 0: fully scrolled past the viewport top.
      if (position.itemTrailingEdge <= 0) continue;
      if (topmost == null || position.index < topmost.index) topmost = position;
    }
    if (topmost == null) return;

    final extent = topmost.itemTrailingEdge - topmost.itemLeadingEdge;
    final double consumed = extent <= 0
        ? 0
        : ((-topmost.itemLeadingEdge) / extent).clamp(0.0, 1.0).toDouble();
    var progress = ((topmost.index + consumed) / itemCount)
        .clamp(0.0, 1.0)
        .toDouble();
    // Bottom snap — see the class doc's Progress bullet: the last
    // item's trailing edge at/above the viewport bottom means the
    // document end is fully visible, which is exactly the webview's
    // progress==1.0 scroll-end. Gated on the document actually
    // scrolling: when BOTH ends are on screen the list never moves, and
    // the webview reports 0 there (scrollY stays 0), so snapping would
    // put every short document at 100% the moment it opens.
    final fitsEntirely =
        positions.any((p) => p.index == 0 && p.itemLeadingEdge >= 0) &&
        positions.any(
          (p) => p.index == itemCount - 1 && p.itemTrailingEdge <= 1,
        );
    if (!fitsEntirely) {
      for (final position in positions) {
        if (position.index == itemCount - 1 && position.itemTrailingEdge <= 1) {
          progress = 1.0;
          break;
        }
      }
    }
    // Null (the footnotes item / a spanless block) keeps the last known
    // line — docState.activeLine IS the last applied line.
    final line =
        _adapter.startLineForIndex(topmost.index) ?? _docState.activeLine;

    _docState.applyScrollSpy(ScrollSpyPayload(progress: progress, line: line));
    _schedulePersist(progress, line);
  }

  void _schedulePersist(double progress, int line) {
    _pendingProgress = progress;
    _pendingLine = line;
    // Trailing-edge throttle: the first update in a window arms the
    // timer, later ones only refresh the pending (latest) value — one
    // write per window.
    _throttleTimer ??= Timer(throttle, () {
      _throttleTimer = null;
      unawaited(_flushPending());
    });
  }

  Future<void> _flushPending() async {
    final progress = _pendingProgress;
    final line = _pendingLine;
    _pendingProgress = null;
    _pendingLine = null;
    if (progress == null || line == null) return;
    final override = _persistOverride;
    if (override != null) return override(progress, line);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_progressKey, progress);
    await prefs.setInt(_lineKey, line);
  }

  /// Detaches from the positions stream, cancels the throttle timer, and
  /// flushes any pending write (the position must survive a pop/kill
  /// right after the last scroll). Idempotent.
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(_handlePositions);
    _throttleTimer?.cancel();
    _throttleTimer = null;
    unawaited(_flushPending());
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.error, required this.tokens});

  final Object? error;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't render this document",
              style: TextStyle(
                fontFamily: AppFonts.sourceSerif4,
                fontSize: AppTypeScale.h3Size,
                fontWeight: AppTypeScale.h3Weight,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.ibmPlexSans,
                fontSize: AppTypeScale.uiTextSize,
                color: tokens.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
