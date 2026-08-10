import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A minimal, host-safe stand-in for `webview_flutter`'s platform
/// implementation, registered as `WebViewPlatform.instance` so
/// `WebViewController()`/`WebViewWidget` can be constructed inside
/// `flutter test` (no real iOS/Android platform view exists there — the
/// assertion `webview_flutter_platform_interface` throws without this is
/// literally "For unit testing, `WebViewPlatform.instance` can be set with
/// your own test implementation.").
///
/// Records enough (`loadedHtml`, `executedScripts`, the registered
/// JavaScript channel callbacks) for reader_test.dart to drive the Reader's
/// non-webview-native chrome and its `ScrollSpy` channel wiring without a
/// device. It does not attempt to simulate real WebView rendering/layout —
/// that stays device-E2E (Task 8), per the task brief.
class FakeWebViewPlatform extends WebViewPlatform {
  final List<FakeWebViewController> controllers = [];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWebViewWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeNavigationDelegate(params);
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  String? loadedHtml;
  final List<String> executedScripts = [];
  final Map<String, void Function(JavaScriptMessage)> channels = {};
  FakeNavigationDelegate? navigationDelegate;

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loadedHtml = html;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    channels[javaScriptChannelParams.name] =
        javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    channels.remove(javaScriptChannelName);
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigationDelegate = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    executedScripts.add(javaScript);
  }

  /// Test helper: simulates a `<channelName>.postMessage(message)` call
  /// from the (fake) loaded page.
  void simulateMessage(String channelName, String message) {
    channels[channelName]?.call(JavaScriptMessage(message: message));
  }
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageFinished;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    // A visible, sized stand-in so layout code (Expanded/SizedBox around
    // the real WebViewWidget in reader.dart) behaves the same as it would
    // around the genuine platform view.
    return const SizedBox.expand(child: ColoredBox(color: Color(0x00000000)));
  }
}
