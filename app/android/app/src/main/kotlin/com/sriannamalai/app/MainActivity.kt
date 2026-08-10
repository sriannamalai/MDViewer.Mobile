package com.sriannamalai.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  private var vaultChannel: VaultChannel? = null
  private var openWithChannel: OpenWithChannel? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    vaultChannel = VaultChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    openWithChannel = OpenWithChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    // Cold start: if this activity was created BY a VIEW intent (an
    // "Open with MDViewer" launch), `intent` here IS that intent.
    openWithChannel?.handleIntent(intent)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    vaultChannel?.onActivityResult(requestCode, resultCode, data)
  }

  // Warm delivery: `singleTop` launch mode (AndroidManifest.xml) routes a
  // second VIEW intent here instead of spawning a new activity instance.
  // `setIntent` keeps `getIntent()` consistent for anything else that reads
  // it later (e.g. a configuration change re-reading the "current" intent).
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    openWithChannel?.handleIntent(intent)
  }
}
