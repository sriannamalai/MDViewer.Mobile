import 'package:mdviewer/mdviewer.dart';

/// The bundled libmdviewer version, or null if the native library can't be
/// resolved in the current process.
///
/// `Mdviewer.instance.version` (`vendor/markdownviewer/flutter/mdviewer/
/// lib/src/library_loader.dart`'s `openMdviewerLibrary`) statically links on
/// iOS and dlopens a bundled `.so` on Android — both resolve fine on a real
/// device/simulator/emulator. On the host Dart VM `flutter test` runs under,
/// neither path applies and it falls back to a `dist/ffi/&lt;os&gt;-&lt;arch&gt;/
/// libmdviewer.*` host build that this repo doesn't produce (Task 1 hit
/// this and reverted its temporary on-host version print for the same
/// reason — see task-1-report.md). Wrapping the access here means the
/// Splash/Settings version lines degrade to a placeholder under
/// `flutter test` instead of crashing every widget test that pumps them.
String? tryMdviewerVersion() {
  try {
    return Mdviewer.instance.version;
  } catch (_) {
    return null;
  }
}
