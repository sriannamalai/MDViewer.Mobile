package com.sriannamalai.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of the `mdviewer/vault` platform channel — folder access
 * via Storage Access Framework (`ACTION_OPEN_DOCUMENT_TREE` +
 * `takePersistableUriPermission`), listing/reading through a
 * [DocumentFile] tree. See
 * `app/lib/src/vault/platform_vault_provider.dart` for the Dart-side
 * contract this implements: `pickFolder` / `restore` / `list` / `read`.
 *
 * Unlike the iOS side, SAF grants don't need an explicit "start/stop scope"
 * — a persisted `content://` tree Uri is usable directly from
 * [android.content.ContentResolver] any time the permission still holds, so
 * every method here just re-derives a [DocumentFile] from the `id` (the
 * tree Uri as a string) it's given rather than caching "the active" one.
 *
 * [MainActivity] owns the actual `ACTION_OPEN_DOCUMENT_TREE` activity
 * result (Android's picker is a `startActivityForResult` round trip, not a
 * synchronous call) and forwards it to [onActivityResult].
 *
 * This channel's actual folder-picker/SAF behavior only runs on a real
 * device or emulator — it is device-E2E-verified, not covered by
 * `flutter test` (see the task-2 report).
 */
class VaultChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
  companion object {
    private const val CHANNEL_NAME = "mdviewer/vault"
    private const val REQUEST_CODE_PICK_FOLDER = 42_017

    /** Directories deeper than this below the picked root aren't descended into — mirrors MDViewer.Desktop's `read_dir_tree` depth bound. */
    private const val MAX_DEPTH = 6
  }

  private val channel = MethodChannel(messenger, CHANNEL_NAME)
  private var pendingPickResult: MethodChannel.Result? = null

  init {
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "pickFolder" -> pickFolder(result)

      "restore" -> {
        val id = call.argument<String>("id")
        if (id == null) {
          result.error("bad_args", "restore requires {id}", null)
        } else {
          result.success(restore(id))
        }
      }

      "list" -> {
        val id = call.argument<String>("id")
        if (id == null) {
          result.error("bad_args", "list requires {id}", null)
        } else {
          result.success(list(id))
        }
      }

      "read" -> {
        val id = call.argument<String>("id")
        val relPath = call.argument<String>("relPath")
        if (id == null || relPath == null) {
          result.error("bad_args", "read requires {id, relPath}", null)
        } else {
          val bytes = read(id, relPath)
          if (bytes == null) result.error("not_found", "could not read \"$relPath\"", null) else result.success(bytes)
        }
      }

      else -> result.notImplemented()
    }
  }

  // region pickFolder

  private fun pickFolder(result: MethodChannel.Result) {
    if (pendingPickResult != null) {
      result.error("busy", "a pickFolder() call is already in progress", null)
      return
    }
    pendingPickResult = result
    val intent =
      Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
      )
    activity.startActivityForResult(intent, REQUEST_CODE_PICK_FOLDER)
  }

  /** Forwarded from [MainActivity.onActivityResult]. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode != REQUEST_CODE_PICK_FOLDER) return
    val result = pendingPickResult ?: return
    pendingPickResult = null

    val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
    if (uri == null) {
      result.success(null) // user cancelled
      return
    }

    activity.contentResolver.takePersistableUriPermission(
      uri,
      Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
    )

    val doc = DocumentFile.fromTreeUri(activity, uri)
    if (doc == null || !doc.isDirectory) {
      result.error("invalid_folder", "picked Uri is not a folder", null)
      return
    }
    val displayName = doc.name ?: uri.lastPathSegment ?: "Folder"
    result.success(mapOf("id" to uri.toString(), "displayName" to displayName))
  }

  // endregion

  private fun restore(id: String): Boolean {
    val uri = parseUri(id) ?: return false
    val hasPermission =
      activity.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
    if (!hasPermission) return false // revoked: the Dart side drops the persisted grant and re-prompts
    val doc = DocumentFile.fromTreeUri(activity, uri) ?: return false
    return doc.isDirectory && doc.exists()
  }

  private fun list(id: String): List<String> {
    val uri = parseUri(id) ?: return emptyList()
    val root = DocumentFile.fromTreeUri(activity, uri) ?: return emptyList()
    val out = mutableListOf<String>()
    walk(root, "", MAX_DEPTH, out)
    return out
  }

  private fun walk(dir: DocumentFile, relPath: String, depth: Int, out: MutableList<String>) {
    if (depth <= 0) return
    val children = runCatching { dir.listFiles() }.getOrNull() ?: return
    for (child in children) {
      val name = child.name ?: continue
      if (name.startsWith(".")) continue // dotfiles/dot-dirs skipped, desktop rule
      val childRelPath = if (relPath.isEmpty()) name else "$relPath/$name"
      if (child.isDirectory) {
        walk(child, childRelPath, depth - 1, out)
      } else if (name.lowercase().endsWith(".md") || name.lowercase().endsWith(".markdown")) {
        out.add(childRelPath)
      }
    }
  }

  private fun read(id: String, relPath: String): ByteArray? {
    val uri = parseUri(id) ?: return null
    var node = DocumentFile.fromTreeUri(activity, uri) ?: return null
    val segments = relPath.split("/").filter { it.isNotEmpty() }
    if (segments.isEmpty()) return null
    for (segment in segments) {
      node = node.findFile(segment) ?: return null
    }
    if (node.isDirectory) return null
    return runCatching { activity.contentResolver.openInputStream(node.uri)?.use { it.readBytes() } }.getOrNull()
  }

  private fun parseUri(id: String): Uri? = runCatching { Uri.parse(id) }.getOrNull()
}
