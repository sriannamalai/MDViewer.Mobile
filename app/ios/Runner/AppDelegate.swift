import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Retained for the app's lifetime — FlutterMethodChannel doesn't retain
  // its handler, so letting this drop would silently stop responding to
  // `mdviewer/vault` calls.
  private var vaultChannel: VaultChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    vaultChannel = VaultChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
