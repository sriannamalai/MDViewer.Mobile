import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Retained for the app's lifetime — FlutterMethodChannel doesn't retain
  // its handler, so letting either of these drop would silently stop
  // responding to their channel's calls.
  private var vaultChannel: VaultChannel?

  // Internal (not private): SceneDelegate reads this to forward open-URL
  // events (`mdviewer/openwith`) — see OpenWithChannel's doc comment for
  // why the URL handling itself lives there, not here.
  var openWithChannel: OpenWithChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    vaultChannel = VaultChannel(messenger: messenger)
    openWithChannel = OpenWithChannel(messenger: messenger)
  }
}
