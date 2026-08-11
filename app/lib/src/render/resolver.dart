import 'dart:convert';
import 'dart:typed_data';

import 'package:mdviewer/mdviewer.dart';

/// Pre-resolved image data URIs for one document render, and the synchronous
/// [MdvResolver] closure built from them.
///
/// The mdviewer plugin's resolver callback runs **synchronously**, one
/// target at a time, on the calling thread during `renderDoc`/`render`
/// (`vendor/markdownviewer/flutter/mdviewer/README.md`'s "Resolver
/// contract") — but `VaultState.resolveRelative` is async (it crosses a
/// platform channel on iOS/Android for a folder-vault read, or an asset-
/// bundle load for the sample vault). Those two facts are incompatible
/// inside a single resolver call, so images can't be resolved lazily
/// on-demand during render. [prefetch] is the fix: walk the parsed AST for
/// every `image` node *before* calling `renderDoc`, resolve each target's
/// bytes asynchronously up front, and hand back a [DocImages] whose
/// [toResolver] closure only ever does a synchronous map lookup during the
/// render — no awaiting, no platform channel, no ffi callback reentrancy.
class DocImages {
  const DocImages(this._dataUris);

  final Map<String, String> _dataUris;

  static const DocImages empty = DocImages({});

  static const int maxBytes = 2 * 1024 * 1024; // 2MB per-image cap

  /// Aggregate cap across one document's whole prefetch batch. 32MB of raw
  /// image bytes (~43MB once base64-encoded into `data:` URIs) bounds the
  /// rendered-HTML string a mobile WebView must hold while still allowing
  /// sixteen worst-case [maxBytes] images — far beyond any reasonable
  /// document, but no longer unbounded (an image-heavy vault doc could
  /// otherwise balloon memory arbitrarily). An image whose bytes would push
  /// the running total past this declines to the library's default
  /// resolution, exactly like an individually oversized one.
  static const int maxTotalBytes = 32 * 1024 * 1024;

  static const Map<String, String> _mimeByExtension = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml',
  };

  /// Walks [parsedDoc] (the `Map` `Mdviewer.parse` decodes to — same
  /// `children`/`value` codec `DocModel.analyze` reads) for every `image`
  /// node's `destination`, and resolves each vault-relative one via
  /// [resolveBytes] (typically `(relPath) =>
  /// vaultState.resolveRelative(entry, relPath)`).
  ///
  /// A target is skipped (declines to the library's default resolution)
  /// when it:
  /// - isn't relative (has a URL scheme — `http://`, `data:`, `mailto:`,
  ///   ... — or is a bare `#fragment`, or starts with `/`),
  /// - has an extension outside the mime table (png/jpg/jpeg/gif/webp/svg),
  /// - fails to resolve (missing file, or [resolveBytes] throws — mirrors
  ///   `VaultState.resolveRelative`'s own "never throws, null on failure"
  ///   contract defensively, in case a caller's closure doesn't),
  /// - resolves to more than [maxBytes],
  /// - or would push the batch's running byte total past [maxTotalBytes].
  static Future<DocImages> prefetch(
    Map<String, dynamic> parsedDoc,
    Future<Uint8List?> Function(String relPath) resolveBytes,
  ) async {
    final targets = <String>{};
    _collectImageTargets(parsedDoc, targets);

    final out = <String, String>{};
    var totalBytes = 0;
    for (final target in targets) {
      if (!_looksRelative(target)) continue;
      final mime = _mimeByExtension[_extensionOf(target)];
      if (mime == null) continue;

      Uint8List? bytes;
      try {
        bytes = await resolveBytes(target);
      } catch (_) {
        bytes = null;
      }
      if (bytes == null) continue;
      if (bytes.lengthInBytes > maxBytes) continue;
      if (totalBytes + bytes.lengthInBytes > maxTotalBytes) continue;
      totalBytes += bytes.lengthInBytes;

      out[target] = 'data:$mime;base64,${base64Encode(bytes)}';
    }
    return DocImages(out);
  }

  /// The synchronous resolver closure for `MdvOptions.resolver`: answers
  /// only `image` targets present in the prefetched map (declining — `null`
  /// — every link and wiki-link kind, and every image this batch didn't
  /// resolve, so default resolution applies to the rest).
  MdvResolver toResolver() {
    return (MdvResolveKind kind, String target) {
      if (kind != MdvResolveKind.image) return null;
      return _dataUris[target];
    };
  }

  static bool _looksRelative(String target) {
    if (target.isEmpty) return false;
    if (target.startsWith('#')) return false;
    if (target.startsWith('/')) return false;
    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasScheme) {
      return false; // http(s):, data:, mailto:, ...
    }
    return true;
  }

  static String _extensionOf(String target) {
    final clean = target.split('#').first.split('?').first;
    final dot = clean.lastIndexOf('.');
    return dot < 0 ? '' : clean.substring(dot).toLowerCase();
  }

  static void _collectImageTargets(Map<String, dynamic> node, Set<String> out) {
    if (node['kind'] == 'image') {
      final destination = node['destination'];
      if (destination is String) out.add(destination);
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map) {
          final map = child is Map<String, dynamic>
              ? child
              : Map<String, dynamic>.from(child);
          _collectImageTargets(map, out);
        }
      }
    }
  }
}
