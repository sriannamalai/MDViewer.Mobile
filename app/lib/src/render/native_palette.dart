import 'package:flutter/material.dart';
import 'package:mdviewer/mdviewer.dart';

import 'renderer.dart';

/// The native engine's themed palettes — the library's real
/// `theme-<mode>.json` + `highlight-<mode>.json` assets, loaded through
/// [DocRenderer.loadPalette].
///
/// ## Why this exists (found on-device in Task 7's E2E)
///
/// `MdvDocumentAdapter`'s `palette: null` resolves the AMBIENT theme's
/// brightness to [MdvPalette.light]/[MdvPalette.dark] — the library's
/// baked-in defaults, which carry the page colors but an EMPTY
/// `tokenColors` map ("code renders in `foreground` until a loaded
/// palette supplies them", per the library's own doc). So every code
/// fence rendered flat monochrome on the native engine while the
/// webview engine syntax-highlighted the same fence: a fidelity
/// regression for the v2 default engine, invisible to host tests
/// (which never load the assets). Handing the adapter a LOADED palette
/// restores the token colors; the tree already carries the highlight
/// token runs (`MdvCodeBlock.runs`, on by default in the tree
/// builder), so nothing else changes.
///
/// ## Both modes, once per process
///
/// Both palettes load together and are cached process-wide: they are
/// theme assets, identical for every document, and a theme flip must
/// restyle in place with no async gap (the Reader picks by brightness
/// at BUILD time, exactly like the adapter did). [ensureLoaded] never
/// throws: a host without a reachable `libmdviewer` (every widget
/// test) gets null, and the Reader falls back to the adapter's
/// ambient-default behavior — the pre-fix rendering, never a crash.
@immutable
class NativePalettes {
  const NativePalettes({required this.light, required this.dark});

  final MdvPalette light;
  final MdvPalette dark;

  /// The palette for [brightness] — the Reader's build-time pick.
  MdvPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static NativePalettes? _cache;

  /// Loads (once per process) and returns both palettes; null when the
  /// assets are unreachable — see the class doc's fallback posture.
  static Future<NativePalettes?> ensureLoaded(DocRenderer renderer) async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final light = await renderer.loadPalette(dark: false);
      final dark = await renderer.loadPalette(dark: true);
      return _cache = NativePalettes(light: light, dark: dark);
    } catch (_) {
      return null;
    }
  }

  /// Clears the process-wide cache. Tests only — the cache is
  /// deliberately global in production (see the class doc).
  @visibleForTesting
  static void resetCacheForTest() => _cache = null;
}
