package com.sriannamalai.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  private var vaultChannel: VaultChannel? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    vaultChannel = VaultChannel(this, flutterEngine.dartExecutor.binaryMessenger)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    vaultChannel?.onActivityResult(requestCode, resultCode, data)
  }
}
