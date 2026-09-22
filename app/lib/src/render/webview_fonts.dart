import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../tokens.dart' show AppFonts;

/// Base64-embeds this app's bundled fonts as `@font-face` `data:` URIs for
/// the WEBVIEW engine ONLY (issue #13).
///
/// `theme/base.css`'s own font stacks are all SYSTEM fonts
/// (`-apple-system`/`ui-monospace`/etc.) — a `loadHtmlString` page has no
/// way to reach files under `assets/fonts/` the way the native engine's
/// own Flutter text widgets do directly (they resolve
/// `tokens.dart`'s [AppFonts] family names straight from the app's
/// `pubspec.yaml` font registration). So the Webview-rendered document
/// body has always used whatever sans/monospace the OS ships, while the
/// native engine and the app's own chrome both use the design's actual
/// Source Serif 4 / IBM Plex Sans / JetBrains Mono.
///
/// [ensureLoaded] embeds the SAME three families — body → IBM Plex Sans,
/// headings → Source Serif 4, code → JetBrains Mono (exactly
/// `tokens.dart`'s `AppTheme._build` mapping) — as self-contained
/// `@font-face` rules keyed to `base.css`'s own selectors, so the mobile
/// prose override's cascade (`renderer.dart`'s `mobileProseOverrideCss`,
/// appended right alongside this in the same `extraCss` string) wins by
/// source order exactly like it already does for size/weight — no
/// `!important` needed.
class WebviewFonts {
  const WebviewFonts._();

  static const List<_FontFile> _files = [
    _FontFile(AppFonts.ibmPlexSans, 400, 'assets/fonts/IBMPlexSans-Regular.ttf'),
    _FontFile(AppFonts.ibmPlexSans, 500, 'assets/fonts/IBMPlexSans-Medium.ttf'),
    _FontFile(
      AppFonts.ibmPlexSans,
      600,
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
    ),
    _FontFile(AppFonts.ibmPlexSans, 700, 'assets/fonts/IBMPlexSans-Bold.ttf'),
    _FontFile(
      AppFonts.sourceSerif4,
      600,
      'assets/fonts/SourceSerif4-SemiBold.ttf',
    ),
    _FontFile(AppFonts.sourceSerif4, 700, 'assets/fonts/SourceSerif4-Bold.ttf'),
    _FontFile(
      AppFonts.jetBrainsMono,
      400,
      'assets/fonts/JetBrainsMono-Regular.ttf',
    ),
    _FontFile(
      AppFonts.jetBrainsMono,
      500,
      'assets/fonts/JetBrainsMono-Medium.ttf',
    ),
  ];

  static String? _cache;

  /// Loads (once per process) and returns the `@font-face` + selector CSS
  /// block described above; null when any bundled asset fails to load —
  /// should never happen for files this app ships itself, but degrading
  /// to "keep the system font stack" beats crashing the Reader over a
  /// font. Cached process-wide: the fonts are static assets, identical
  /// for every document, so there is no per-render reason to re-encode
  /// ~1.4MB of TTF bytes to base64 on every single Webview render.
  static Future<String?> ensureLoaded() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _load();
  }

  static Future<String?> _load() async {
    try {
      final css = StringBuffer();
      for (final file in _files) {
        final data = await rootBundle.load(file.asset);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        css.write(
          "@font-face{font-family:'${file.family}';font-weight:"
          "${file.weight};src:url(data:font/ttf;base64,"
          "${base64Encode(bytes)}) format('truetype');}\n",
        );
      }
      css.write(_selectorCss);
      return _cache = css.toString();
    } catch (_) {
      return null;
    }
  }

  /// Re-points `base.css`'s font-consuming selectors at the embedded
  /// families, keeping each one's ORIGINAL system-font stack as a
  /// fallback (a `@font-face` load failure degrades to the same stack
  /// `base.css` itself would have used). Scoped to EXACTLY the elements
  /// `tokens.dart`'s `AppTheme._build` gives a non-default family
  /// natively — h1/h2/h3 only (h4-h6 keep the default body family on
  /// both engines, matching `AppTheme`'s `headlineLarge`/`Medium`/
  /// `Small`-only override) — so the two engines render identically,
  /// not just "some custom font instead of the system one".
  static final String _selectorCss =
      "body.markdown-body{font-family:'${AppFonts.ibmPlexSans}',"
      '-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,'
      'sans-serif,"Apple Color Emoji","Segoe UI Emoji";}\n'
      '.markdown-body h1,.markdown-body h2,.markdown-body h3{font-family:'
      "'${AppFonts.sourceSerif4}',-apple-system,BlinkMacSystemFont,"
      '"Segoe UI",Helvetica,Arial,sans-serif;}\n'
      '.markdown-body code,.markdown-body pre,.markdown-body kbd,'
      ".markdown-body .md-code-lang,.markdown-body .md-code-copy{"
      "font-family:'${AppFonts.jetBrainsMono}',ui-monospace,SFMono-Regular,"
      '"SF Mono",Menlo,Consolas,"Liberation Mono",monospace;}\n';

  /// Clears the process-wide cache. Tests only — the cache is
  /// deliberately global in production (see [ensureLoaded]'s doc
  /// comment).
  @visibleForTesting
  static void resetCacheForTest() => _cache = null;
}

class _FontFile {
  const _FontFile(this.family, this.weight, this.asset);

  final String family;
  final int weight;
  final String asset;
}
