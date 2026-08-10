import Flutter
import UIKit

/// Overrides `FlutterSceneDelegate`'s URL-opening callbacks to forward
/// "Open with MDViewer" deliveries to `OpenWithChannel` — cold start via
/// `willConnectTo`'s `connectionOptions.urlContexts` (a scene created *by*
/// opening a file — `application(_:open:options:)` is never called once a
/// `UISceneDelegate` is in play, per Apple's docs), warm via
/// `openURLContexts` (a file opened while this scene is already running).
/// `super` is called first in both overrides — `FlutterSceneDelegate`'s own
/// implementation forwards the same events to its
/// `FlutterPluginSceneLifeCycleDelegate` (registered Flutter plugins'
/// scene-lifecycle hooks), which this app still needs even though it isn't
/// one of the plugins listening.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url {
      openWithChannel?.handleOpen(url: url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if let url = URLContexts.first?.url {
      openWithChannel?.handleOpen(url: url)
    }
  }

  private var openWithChannel: OpenWithChannel? {
    (UIApplication.shared.delegate as? AppDelegate)?.openWithChannel
  }
}
