import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A file delivered via the OS "Open with MDViewer" flow — parsed from the
/// `mdviewer/openwith` platform channel's payload map (iOS:
/// `ios/Runner/OpenWithChannel.swift`; Android:
/// `android/.../OpenWithChannel.kt`).
@immutable
class OpenWithFile {
  const OpenWithFile({required this.name, required this.bytes, this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;

  /// Parses a channel payload (`{name, bytes, mimeType}`), returning null
  /// for anything malformed. This is a trust boundary the same way
  /// `scrollspy.dart`'s `ScrollSpyPayload.tryParse` is: the payload is
  /// produced by native code handling an arbitrary OS-delivered file (or,
  /// in principle, a hand-crafted platform-channel call), so it must
  /// degrade to "ignore this delivery", never throw into the caller.
  static OpenWithFile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;

    final bytesRaw = raw['bytes'];
    final Uint8List? bytes = switch (bytesRaw) {
      Uint8List b => b,
      List<int> l => Uint8List.fromList(l),
      _ => null,
    };
    if (bytes == null) return null;

    final mimeType = raw['mimeType'];
    return OpenWithFile(
      name: name,
      bytes: bytes,
      mimeType: mimeType is String ? mimeType : null,
    );
  }

  @override
  String toString() => 'OpenWithFile($name, ${bytes.length} bytes)';
}

/// The Dart half of the `mdviewer/openwith` platform channel — see the
/// native sides' doc comments (`ios/Runner/OpenWithChannel.swift`,
/// `android/.../OpenWithChannel.kt`) for the cold/warm handshake this
/// implements.
///
/// [takeInitialFile] must be called exactly once, at app startup (see
/// `main.dart`'s wiring): it both consumes any file that arrived before
/// Dart was ready (a cold "Open with" launch) *and* flips the native side's
/// "Dart is ready" flag, so any file delivered afterward is pushed via
/// [listen]'s callback instead of buffered for a `takeInitialFile` that
/// will never come again.
class OpenWithChannel {
  OpenWithChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('mdviewer/openwith');

  final MethodChannel _channel;

  Future<OpenWithFile?> takeInitialFile() async {
    final result = await _channel.invokeMethod<Object?>('takeInitialFile');
    return OpenWithFile.tryParse(result);
  }

  /// Registers the handler for warm deliveries (native-side `onOpenFile`
  /// calls while the app is already running). This app only ever has one
  /// listener, wired once in `main.dart`; calling this again replaces it.
  void listen(void Function(OpenWithFile file) onOpenFile) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenFile') {
        final file = OpenWithFile.tryParse(call.arguments);
        if (file != null) onOpenFile(file);
      }
      return null;
    });
  }
}
