import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'resolver.dart';

/// The native engine's image resolution — the `MdvImageResolver` the
/// Reader hands `NativeDocView`/`MdvDocumentAdapter` for one document.
///
/// The adapter's resolver callback is ASYNC (a Future-returning
/// `MdvImageResolver`), so unlike the webview pipeline
/// there is NO pre-resolve pass here: each image resolves lazily,
/// on-demand, straight through the vault's async read
/// (`VaultState.resolveRelative` — a platform channel for folder vaults,
/// an asset load for the sample vault). `DocImages.prefetch` stays,
/// untouched, for the webview engine and the share export.
///
/// ## Identity contract (the plugin memoizes on the callback)
///
/// The plugin's image widget re-resolves whenever the callback compares
/// UNEQUAL across builds — and every inline closure is a fresh, unequal
/// object per build. So the Reader creates ONE instance per document (at
/// load, capturing the entry + vault read once) and holds it as a state
/// field; tear-offs of one instance's [call] always compare equal, so
/// rebuilds (Aa steps, theme flips, scroll setStates) never refetch.
///
/// ## Target rules — shared with the webview pre-resolver, not forked
///
/// [DocImages.looksRelativeTarget] / [DocImages.extensionOf] /
/// [DocImages.allowsImageExtension] are the ONE URL policy both engines
/// apply. The native path takes the allowlist MINUS `.svg`: Flutter's
/// image codec cannot decode SVG, so it declines to the plugin's
/// alt-text placeholder — a documented native-engine limitation the
/// webview engine covers. Anything declined, missing, throwing, or over
/// the [maxBytes] sanity cap resolves to null (alt-text placeholder);
/// [call] NEVER throws.
///
/// No aggregate byte cap on this path (unlike [DocImages.maxTotalBytes]):
/// decoded images live in Flutter's `ImageCache`, which evicts under
/// pressure — only the single-read sanity cap below applies, bounding a
/// pathological transfer over the platform channel.
class NativeImageResolver {
  NativeImageResolver({required this.resolveBytes});

  /// 20MB per-image sanity cap — reads past it decline to null.
  static const int maxBytes = 20 * 1024 * 1024;

  /// The vault read for this document, typically
  /// `(relPath) => vault.resolveRelative(entry, relPath)` — captured once
  /// at document load (a vault re-grant mid-read is out of scope).
  final Future<Uint8List?> Function(String relPath) resolveBytes;

  /// The `MdvImageResolver` body. [alt] is unused (the plugin renders the
  /// alt-text placeholder itself on a null).
  Future<ImageProvider?> call(String url, String alt) async {
    if (!DocImages.looksRelativeTarget(url)) return null;
    final ext = DocImages.extensionOf(url);
    if (!DocImages.allowsImageExtension(ext) || ext == '.svg') return null;

    Uint8List? bytes;
    try {
      bytes = await resolveBytes(url);
    } catch (_) {
      // resolveRelative's own contract is "never throws, null on
      // failure" — mirror it defensively for callers whose closure
      // doesn't (same posture as DocImages.prefetch).
      bytes = null;
    }
    if (bytes == null) return null;
    if (bytes.lengthInBytes > maxBytes) return null;
    return MemoryImage(bytes);
  }
}
