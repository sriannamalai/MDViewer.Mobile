package com.sriannamalai.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of the `mdviewer/openwith` platform channel — delivers a
 * single "Open with MDViewer" file from the manifest's `VIEW` intent-filters
 * (`AndroidManifest.xml`), read via [android.content.ContentResolver]. See
 * `app/lib/src/vault/open_with_channel.dart` for the Dart-side contract:
 * `takeInitialFile` (cold, pulled once at startup) / `onOpenFile` (warm,
 * pushed).
 *
 * Cold vs. warm is arbitrated the same explicit handshake the iOS side
 * (`ios/Runner/OpenWithChannel.swift`) uses rather than relying on
 * undocumented platform-channel message buffering: the first Dart-side call
 * is always `takeInitialFile`, which both consumes whatever arrived before
 * Dart was ready ([pendingFile]) and flips [dartReady]. Anything delivered
 * after that flip is pushed straight to Dart via `onOpenFile`.
 *
 * [MainActivity] calls [handleIntent] twice: once in `configureFlutterEngine`
 * with its own launch `intent` (cold start — a `VIEW` intent *is* how the
 * activity got created), and again from `onNewIntent` (warm — `singleTop`
 * launch mode means the same activity instance receives a second `VIEW`
 * intent instead of a new one being created, which is exactly what lets a
 * long-lived engine/channel handle it without a relaunch).
 *
 * This channel's actual intent-delivery behavior only runs on a real device
 * or emulator receiving a genuine `VIEW` intent — it is device-E2E verified
 * (Task 8), not covered by `flutter test` (same caveat `VaultChannel`'s doc
 * comment notes for the sibling `mdviewer/vault` channel).
 */
class OpenWithChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
  companion object {
    private const val CHANNEL_NAME = "mdviewer/openwith"
  }

  private val channel = MethodChannel(messenger, CHANNEL_NAME)
  private var pendingFile: Map<String, Any?>? = null
  private var dartReady = false

  init {
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "takeInitialFile" -> {
        dartReady = true
        val file = pendingFile
        pendingFile = null
        result.success(file)
      }
      else -> result.notImplemented()
    }
  }

  /** No-op for anything that isn't a `VIEW` intent carrying a data [Uri] — safe to call unconditionally from both call sites. */
  fun handleIntent(intent: Intent?) {
    if (intent == null || intent.action != Intent.ACTION_VIEW) return
    val uri = intent.data ?: return
    val payload = readFile(uri) ?: return

    if (dartReady) {
      channel.invokeMethod("onOpenFile", payload)
    } else {
      pendingFile = payload
    }
  }

  private fun readFile(uri: Uri): Map<String, Any?>? {
    val resolver = activity.contentResolver
    val bytes = runCatching { resolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() ?: return null
    val name = queryDisplayName(uri) ?: uri.lastPathSegment ?: "Untitled.md"
    val mimeType = resolver.getType(uri) ?: "text/markdown"
    return mapOf("name" to name, "mimeType" to mimeType, "bytes" to bytes)
  }

  /** `content://` URIs commonly expose their human-readable filename only via [OpenableColumns.DISPLAY_NAME], not the URI's own last path segment (often an opaque document ID). */
  private fun queryDisplayName(uri: Uri): String? =
    runCatching {
      activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (!cursor.moveToFirst()) return@use null
        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (index < 0) null else cursor.getString(index)
      }
    }.getOrNull()
}
