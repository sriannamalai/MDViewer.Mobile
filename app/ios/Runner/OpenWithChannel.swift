import Flutter
import UIKit
import UniformTypeIdentifiers

/// The iOS half of the `mdviewer/openwith` platform channel — delivers a
/// single "Open with MDViewer" file (Info.plist's `CFBundleDocumentTypes` +
/// `LSSupportsOpeningDocumentsInPlace`) from either a cold launch
/// (`SceneDelegate.scene(_:willConnectTo:options:)`'s `connectionOptions
/// .urlContexts`) or a warm delivery while the app is already running
/// (`SceneDelegate.scene(_:openURLContexts:)`). See
/// `app/lib/src/vault/open_with_channel.dart` for the Dart-side contract:
/// `takeInitialFile` (cold, pulled once at startup) / `onOpenFile` (warm,
/// pushed).
///
/// Cold vs. warm is arbitrated with a tiny explicit handshake rather than
/// relying on undocumented platform-channel message buffering: the very
/// first Dart-side call is always `takeInitialFile`, which both consumes
/// whatever arrived before Dart was ready (`pendingFile`) and flips
/// `dartReady`. Anything delivered after that flip is pushed straight to
/// Dart via `onOpenFile` instead of being buffered for a
/// `takeInitialFile` call that will never come again.
///
/// This channel's actual open-URL delivery only runs on a real device or
/// simulator receiving a genuine `UIOpenURLContext` — it is device-E2E
/// verified (Task 8), not covered by `flutter test` (see `VaultChannel`'s
/// doc comment for the same caveat on the sibling `mdviewer/vault`
/// channel).
final class OpenWithChannel: NSObject {
  static let channelName = "mdviewer/openwith"

  private let channel: FlutterMethodChannel
  private var pendingFile: [String: Any]?
  private var dartReady = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takeInitialFile":
      dartReady = true
      let file = pendingFile
      pendingFile = nil
      result(file)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Called by `SceneDelegate` for both cold-start and warm delivery — a
  /// security-scoped, "open in place" URL per
  /// `LSSupportsOpeningDocumentsInPlace`. Reads the file's bytes while the
  /// security scope is held, then releases it immediately: v1's open-with
  /// flow is a one-shot read, not a held grant (unlike the folder-vault
  /// bookmarks `VaultChannel` persists) — see task-7-report.md's "relative
  /// images decline for open-with docs" limitation, which follows directly
  /// from not keeping this scope (or any folder context) around.
  func handleOpen(url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    guard let data = try? Data(contentsOf: url) else { return }
    let payload: [String: Any] = [
      "name": url.lastPathComponent,
      "mimeType": mimeType(for: url),
      "bytes": FlutterStandardTypedData(bytes: data),
    ]

    if dartReady {
      channel.invokeMethod("onOpenFile", arguments: payload)
    } else {
      pendingFile = payload
    }
  }

  private func mimeType(for url: URL) -> String {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return "text/markdown" }
    return type.preferredMIMEType ?? "text/markdown"
  }
}
