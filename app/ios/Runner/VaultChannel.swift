import Flutter
import UIKit
import UniformTypeIdentifiers

/// The iOS half of the `mdviewer/vault` platform channel — folder access via
/// `UIDocumentPickerViewController` (folder mode, "open" not "import" so the
/// picked folder is never copied into the app sandbox) + security-scoped
/// bookmarks. See `app/lib/src/vault/platform_vault_provider.dart` for the
/// Dart-side contract this implements: `pickFolder` / `restore` / `list` /
/// `read`.
///
/// Only one folder is "active" (its security scope started) at a time,
/// matching the Dart-side `PlatformVaultProvider`'s one-grant-at-a-time
/// model (v1 non-goal: multiple vaults). `pickFolder`/`restore` stop any
/// previously-active scope before starting the new one so scopes never leak
/// across a folder switch.
///
/// This channel's actual folder-picker/bookmark behavior only runs on a
/// real device or simulator — it is device-E2E-verified, not covered by
/// `flutter test` (see the task-2 report).
final class VaultChannel: NSObject {
  static let channelName = "mdviewer/vault"

  /// Directories more than this many levels below the picked root are not
  /// descended into — mirrors MDViewer.Desktop's `read_dir_tree` depth
  /// bound.
  private static let maxDepth = 6

  private let channel: FlutterMethodChannel
  private var activeURL: URL?
  private var pendingPickCompletion: ((URL?) -> Void)?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickFolder":
      pickFolder(result: result)

    case "restore":
      guard let id = stringArg(call, "id") else {
        result(badArgs("restore requires {id}"))
        return
      }
      result(restore(id: id))

    case "list":
      guard let id = stringArg(call, "id") else {
        result(badArgs("list requires {id}"))
        return
      }
      result(list(id: id))

    case "read":
      guard let id = stringArg(call, "id"), let relPath = stringArg(call, "relPath") else {
        result(badArgs("read requires {id, relPath}"))
        return
      }
      result(read(id: id, relPath: relPath))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func stringArg(_ call: FlutterMethodCall, _ key: String) -> String? {
    (call.arguments as? [String: Any])?[key] as? String
  }

  private func badArgs(_ message: String) -> FlutterError {
    FlutterError(code: "bad_args", message: message, details: nil)
  }

  // MARK: - pickFolder

  private func pickFolder(result: @escaping FlutterResult) {
    guard pendingPickCompletion == nil else {
      // Mirrors the Android side: without this, a second concurrent call
      // would overwrite pendingPickCompletion, orphaning the first call's
      // FlutterResult — its Dart Future would simply never complete.
      result(FlutterError(code: "busy", message: "a pickFolder() call is already in progress", details: nil))
      return
    }
    guard let rootViewController = Self.rootViewController() else {
      result(FlutterError(code: "no_root_vc", message: "no root view controller to present the picker from", details: nil))
      return
    }

    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
    picker.allowsMultipleSelection = false
    picker.delegate = self

    pendingPickCompletion = { [weak self] url in
      guard let self else { return }
      guard let url else {
        result(nil) // user cancelled
        return
      }
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(code: "scope_failed", message: "startAccessingSecurityScopedResource failed", details: nil))
        return
      }
      do {
        let bookmark = try url.bookmarkData()
        self.activateScope(url: url)
        result(["id": bookmark.base64EncodedString(), "displayName": url.lastPathComponent])
      } catch {
        url.stopAccessingSecurityScopedResource()
        result(FlutterError(code: "bookmark_failed", message: "\(error)", details: nil))
      }
    }
    rootViewController.present(picker, animated: true)
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    if let windowScene = activeScene, let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
      return window.rootViewController
    }
    return UIApplication.shared.delegate?.window??.rootViewController
  }

  // MARK: - restore

  private func restore(id: String) -> Bool {
    guard let bookmark = Data(base64Encoded: id) else { return false }
    var isStale = false
    guard
      let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
    else {
      return false
    }
    // Stale bookmark: the Dart side drops the persisted grant and
    // re-prompts via pickFolder() rather than trying to use a URL that may
    // no longer point at the right place.
    if isStale { return false }
    guard url.startAccessingSecurityScopedResource() else { return false }
    activateScope(url: url)
    return true
  }

  private func activateScope(url: URL) {
    activeURL?.stopAccessingSecurityScopedResource()
    activeURL = url
  }

  // MARK: - list

  private func list(id: String) -> [String] {
    guard let root = activeURL else { return [] }
    var out: [String] = []
    walk(dir: root, relPath: "", depth: Self.maxDepth, into: &out)
    return out
  }

  private func walk(dir: URL, relPath: String, depth: Int, into out: inout [String]) {
    guard depth > 0 else { return }
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else { return }

    for entry in entries {
      let name = entry.lastPathComponent
      if name.hasPrefix(".") { continue } // dotfiles/dot-dirs skipped, desktop rule
      let childRelPath = relPath.isEmpty ? name : "\(relPath)/\(name)"
      let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      if isDir {
        walk(dir: entry, relPath: childRelPath, depth: depth - 1, into: &out)
      } else if name.lowercased().hasSuffix(".md") || name.lowercased().hasSuffix(".markdown") {
        out.append(childRelPath)
      }
    }
  }

  // MARK: - read

  private func read(id: String, relPath: String) -> FlutterStandardTypedData? {
    guard let root = activeURL else { return nil }
    let target = root.appendingPathComponent(relPath)
    // Belt-and-suspenders: the Dart side (VaultPath.resolve) already
    // rejects any relPath that would walk above the vault root before it
    // ever reaches here, but refuse to serve anything outside the picked
    // root regardless of how the path arrived.
    //
    // A plain hasPrefix(root.path) is the classic sibling-directory flaw:
    // "/Users/x/VaultRoot-evil" has "/Users/x/VaultRoot" as a raw string
    // prefix without being inside it. Comparing against the root path with
    // a trailing separator closes that, while still accepting the target
    // legitimately BEING the root itself (relPath == "").
    let targetPath = target.standardizedFileURL.path
    let rootPath = root.standardizedFileURL.path
    let rootPathWithSeparator = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard targetPath == rootPath || targetPath.hasPrefix(rootPathWithSeparator) else { return nil }
    guard let data = try? Data(contentsOf: target) else { return nil }
    return FlutterStandardTypedData(bytes: data)
  }
}

extension VaultChannel: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    pendingPickCompletion?(urls.first)
    pendingPickCompletion = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPickCompletion?(nil)
    pendingPickCompletion = nil
  }
}
