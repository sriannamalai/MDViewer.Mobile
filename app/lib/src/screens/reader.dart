import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
import 'outline_sheet.dart';

/// The Reader — design/README.md §02: blurred header (back/filename+meta/
/// share), a 2px scroll-progress hairline, the rendered document in a
/// [WebViewWidget], and a blurred bottom bar (Outline pill, current
/// section·%, an "Aa" text-size control).
///
/// Owns the full parse-once/render-many pipeline: reads [entry]'s bytes,
/// parses them once (`renderer.dart`'s [DocRenderer]), pre-resolves its
/// relative images (`resolver.dart`'s [DocImages]) before the first render
/// (the plugin's resolver callback is synchronous; the vault read isn't —
/// see resolver.dart's doc comment), injects the scrollspy script
/// (`scrollspy.dart`) into the rendered HTML, and re-renders (preserving
/// scroll position) whenever the effective theme or text-scale step
/// changes.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.entry, this.renderer});

  final VaultEntry entry;

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
  late final WebViewController _controller;

  _LoadStatus _status = _LoadStatus.loading;
  Object? _error;
  Map<String, dynamic>? _parsedDoc;

  /// Set once, in [_load], the moment the document's [DocModel] is known.
  /// Its own listener (added right after construction) triggers a local
  /// `setState` on every scrollspy update, so the header meta/hairline/
  /// bottom bar redraw without needing an `InheritedWidget` for a value
  /// that never leaves this single screen in v1 (Task 6's outline sheet is
  /// the first consumer that would need it exposed further, and can wrap
  /// its own `ChangeNotifierProvider` around this same instance then).
  ReaderDocState? _docState;

  double? _pendingRestoreProgress;
  bool _rerendering = false;
  double _renderedScale = AppState.defaultTextScale;
  Brightness? _renderedBrightness;

  String get _prefsKey =>
      'reader.scroll.${widget.entry.source.name}:${widget.entry.relPath}';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        scrollSpyChannelName,
        onMessageReceived: _handleScrollSpyMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageFinished: _handlePageFinished,
        ),
      );
    unawaited(_load());
  }

  @override
  void dispose() {
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
      final images = await DocImages.prefetch(
        parsed,
        (relPath) => vault.resolveRelative(widget.entry, relPath),
      );

      final prefs = await SharedPreferences.getInstance();
      _pendingRestoreProgress = prefs.getDouble(_prefsKey);

      if (!mounted) return;
      final docState = ReaderDocState(model: model)
        ..addListener(_handleDocStateChanged);
      setState(() {
        _parsedDoc = parsed;
        _docState = docState;
        _status = _LoadStatus.ready;
      });
      await _renderInto(images: images);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _LoadStatus.error;
        _error = error;
      });
    }
  }

  Future<void> _renderInto({DocImages? images}) async {
    final doc = _parsedDoc;
    if (doc == null) return;
    final appState = context.read<AppState>();
    final brightness = Theme.of(context).brightness;
    final scale = appState.textScale;

    final html = _renderer.render(
      doc,
      brightness: brightness,
      textScale: scale,
      resolver: (images ?? DocImages.empty).toResolver(),
    );
    _renderedScale = scale;
    _renderedBrightness = brightness;
    await _controller.loadHtmlString(injectScrollSpy(html));
  }

  void _handleScrollSpyMessage(JavaScriptMessage message) {
    final payload = ScrollSpyPayload.tryParse(message.message);
    if (payload == null) return;
    _docState?.applyScrollSpy(payload);
    unawaited(_persistScroll(payload.progress));
  }

  Future<void> _persistScroll(double progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, progress);
  }

  void _handlePageFinished(String url) {
    final restore = _pendingRestoreProgress;
    if (restore != null) {
      _pendingRestoreProgress = null;
      unawaited(_controller.runJavaScript(scrollToProgressScript(restore)));
    }
  }

  FutureOr<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) {
    final uri = Uri.tryParse(request.url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      unawaited(_openExternal(uri));
      return NavigationDecision.prevent;
    }
    if (uri != null && uri.scheme.isEmpty && !request.url.startsWith('data:')) {
      unawaited(_openInternalRelative(request.url));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
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

  Future<void> _share() async {
    final doc = _parsedDoc;
    if (doc == null || !mounted) return;
    try {
      final brightness = Theme.of(context).brightness;
      final html = _renderer.render(
        doc,
        brightness: brightness,
        textScale: context.read<AppState>().textScale,
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
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: SafeArea(
          top: false,
          child: Column(
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
            ],
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
    OutlineSheet.show(
      context,
      docState: docState,
      onTapHeading: (line) {
        unawaited(_controller.runJavaScript(scrollToLineScript(line)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appState = context.watch<AppState>();
    final brightness = Theme.of(context).brightness;

    if (_status == _LoadStatus.ready &&
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
        return WebViewWidget(controller: _controller);
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
                Flexible(
                  child: Text(
                    '$sectionLabel · $percent%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.jetBrainsMono,
                      fontSize: AppTypeScale.readerSectionSize,
                      color: tokens.text3,
                    ),
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
