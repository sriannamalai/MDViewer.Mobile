import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgBytesLoader, vg;

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
/// apply — including `.svg`, since [_rasterizeSvg] below closes what used
/// to be a native-only gap (Flutter's own image codecs cannot decode SVG,
/// so raw bytes can never become a [MemoryImage]; rasterizing via
/// `flutter_svg`'s vector-graphics backend first is what makes an SVG
/// resolvable here at all). Anything declined, missing, throwing, or over
/// the [maxBytes] sanity cap resolves to null (alt-text placeholder);
/// [call] NEVER throws.
///
/// No aggregate byte cap on this path (unlike [DocImages.maxTotalBytes]):
/// decoded images live in Flutter's `ImageCache`, which evicts under
/// pressure — only the single-read sanity cap below applies, bounding a
/// pathological transfer over the platform channel.
class NativeImageResolver {
  NativeImageResolver({required this.resolveBytes});

  /// 20MB per-image sanity cap — reads past it decline to null. Applies
  /// to the source bytes for every extension, SVG (text) included.
  static const int maxBytes = 20 * 1024 * 1024;

  /// SVG rasterization upscale factor over the SVG's own intrinsic
  /// (viewBox) size. [call]'s signature carries no target widget size or
  /// device pixel ratio — the plugin's `MdvImageResolver` only ever hands
  /// back `(url, alt)` — so there is no layout information to rasterize
  /// exactly against. A fixed multiplier keeps typical documentation
  /// diagrams/icons reasonably crisp on a 2x/3x display without the
  /// unbounded blow-up an arbitrary caller-chosen size could invite.
  static const double svgRasterScale = 2.0;

  /// Hard cap, in physical pixels, on the rasterized SVG's longer side —
  /// bounds worst-case decode memory/CPU for a pathological viewBox (e.g.
  /// a poster-sized diagram), independent of [svgRasterScale].
  static const int maxSvgRasterDimension = 2048;

  /// The vault read for this document, typically
  /// `(relPath) => vault.resolveRelative(entry, relPath)` — captured once
  /// at document load (a vault re-grant mid-read is out of scope).
  final Future<Uint8List?> Function(String relPath) resolveBytes;

  /// The `MdvImageResolver` body. [alt] is unused (the plugin renders the
  /// alt-text placeholder itself on a null).
  Future<ImageProvider?> call(String url, String alt) async {
    if (!DocImages.looksRelativeTarget(url)) return null;
    final ext = DocImages.extensionOf(url);
    if (!DocImages.allowsImageExtension(ext)) return null;

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
    if (ext == '.svg') return _rasterizeSvg(bytes);
    return MemoryImage(bytes);
  }

  /// Rasterizes SVG [bytes] into a [ui.Image]-backed [ImageProvider],
  /// since none of Flutter's built-in image codecs decode SVG. Declines
  /// to null — never throws, mirroring [call]'s contract — on malformed
  /// SVG, a degenerate/zero intrinsic size, or any rendering failure.
  ///
  /// The intermediate [ui.PictureRecorder] draws the vector picture
  /// scaled onto a fresh canvas rather than calling `picture.toImage`
  /// directly on the decoded [ui.Picture] at its intrinsic size: the
  /// latter rasterizes at the SVG's own viewBox resolution (often tiny —
  /// e.g. `24x24` for an icon), which then upscales blurrily once laid
  /// out at a larger widget size. Scaling the canvas before drawing keeps
  /// the rasterization itself sharp up to [svgRasterScale] /
  /// [maxSvgRasterDimension].
  static Future<ImageProvider?> _rasterizeSvg(Uint8List bytes) async {
    try {
      final pictureInfo = await vg.loadPicture(SvgBytesLoader(bytes), null);
      final srcWidth = pictureInfo.size.width;
      final srcHeight = pictureInfo.size.height;
      if (srcWidth <= 0 || srcHeight <= 0 || !srcWidth.isFinite || !srcHeight.isFinite) {
        pictureInfo.picture.dispose();
        return null;
      }

      final scale = <double>[
        svgRasterScale,
        maxSvgRasterDimension / srcWidth,
        maxSvgRasterDimension / srcHeight,
      ].reduce((a, b) => a < b ? a : b);
      final width = (srcWidth * scale).round().clamp(1, maxSvgRasterDimension);
      final height = (srcHeight * scale).round().clamp(
        1,
        maxSvgRasterDimension,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(width / srcWidth, height / srcHeight);
      canvas.drawPicture(pictureInfo.picture);
      final rasterPicture = recorder.endRecording();
      pictureInfo.picture.dispose();

      final image = await rasterPicture.toImage(width, height);
      rasterPicture.dispose();
      return _DecodedImageProvider(image);
    } catch (_) {
      return null;
    }
  }
}

/// An [ImageProvider] wrapping an already-decoded [ui.Image] — the
/// terminal step of [NativeImageResolver._rasterizeSvg], where the image
/// is produced up front by rasterizing a vector picture rather than
/// decoded from an encoded byte stream (there is no [ui.Codec] for
/// "already a [ui.Image]"). Never compares equal to another instance:
/// each call rasterizes a fresh image with no content-addressed cache, so
/// this only ever needs to serve the single `ImageStream` the plugin
/// attaches to immediately after [NativeImageResolver.call] returns it.
class _DecodedImageProvider extends ImageProvider<_DecodedImageProvider> {
  _DecodedImageProvider(this._image);

  final ui.Image _image;

  @override
  Future<_DecodedImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DecodedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _DecodedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: _image, scale: 1.0)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _DecodedImageProvider && other._image == _image);

  @override
  int get hashCode => _image.hashCode;
}
