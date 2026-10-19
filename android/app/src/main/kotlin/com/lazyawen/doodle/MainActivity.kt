package com.lazyawen.doodle

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

/**
 * Android storage bridge.
 *
 * Modern Android (11+) refuses raw writes under /storage/emulated/0, so the
 * "put my drawings in a folder I can find" feature has to go through
 * MediaStore (public gallery folders) and SAF (user-picked folders) instead of
 * File(). Both paths are exposed to Dart over one MethodChannel.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "doodle/save"
        const val PICK_FOLDER_REQUEST = 4711
        const val APP_FOLDER = "涂想"
    }

    private var saveChannel: MethodChannel? = null
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        saveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        saveChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                    "savePng" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name")
                        val folder = call.argument<String>("folder") ?: APP_FOLDER
                        if (bytes == null || name == null) {
                            result.error("bad_args", "bytes/name missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveViaMediaStore(bytes, folder, name))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }

                    "pickFolder" -> {
                        if (pendingFolderResult != null) {
                            result.error("busy", "a folder request is already running", null)
                            return@setMethodCallHandler
                        }
                        pendingFolderResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        try {
                            startActivityForResult(intent, PICK_FOLDER_REQUEST)
                        } catch (e: Exception) {
                            pendingFolderResult = null
                            result.error("pick_failed", e.message, null)
                        }
                    }

                    "saveToTree" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name")
                        val treeUri = call.argument<String>("treeUri")
                        if (bytes == null || name == null || treeUri == null) {
                            result.error("bad_args", "bytes/name/treeUri missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToTree(bytes, Uri.parse(treeUri), name))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
        }
    }

    /**
     * Writes into a public gallery folder (Pictures/涂想 by default) and returns
     * a human-readable path such as /storage/emulated/0/Pictures/涂想/xxx.png.
     */
    private fun saveViaMediaStore(bytes: ByteArray, folder: String, name: String): String {
        val baseName = name.substringBeforeLast('.').ifBlank { "Doodle" }
        val mimeType = "image/png"

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "$baseName.png")
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // RELATIVE_PATH only applies on 29+; older versions use DATA.
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/$folder")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            } else {
                @Suppress("DEPRECATION")
                put(
                    MediaStore.MediaColumns.DATA,
                    "${legacyPicturesDir()}/$folder/$baseName.png"
                )
            }
        }

        val resolver = contentResolver
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore refused the insert")

        try {
            val stream: OutputStream? = resolver.openOutputStream(uri)
            if (stream == null) {
                resolver.delete(uri, null, null)
                throw IllegalStateException("cannot open output stream")
            }
            stream.use { it.write(bytes) }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        return displayPath(uri, folder, "$baseName.png")
    }

    /** Writes into a folder the user picked with the system folder picker. */
    private fun saveToTree(bytes: ByteArray, treeUri: Uri, name: String): String {
        val baseName = name.substringBeforeLast('.').ifBlank { "Doodle" }
        val picked = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("folder is no longer available")

        // Keep the persistable grant alive across restarts.
        contentResolver.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )

        val existing = picked.findFile("$baseName.png")
        val target = existing ?: picked.createFile("image/png", "$baseName.png")
            ?: throw IllegalStateException("cannot create the file in that folder")

        contentResolver.openOutputStream(target.uri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("cannot open the file for writing")

        return displayPath(target.uri, picked.name ?: "", "$baseName.png")
    }

    /**
     * A best-effort readable location. MediaStore/SAF URIs do not map to a real
     * path on modern Android, but users still want something they can paste into
     * a file manager, so fall back to the well-known layout.
     */
    private fun displayPath(uri: Uri, folder: String, fileName: String): String {
        val fromTree = runCatching { treePath(uri) }.getOrNull()
        if (!fromTree.isNullOrEmpty()) return fromTree

        val root = externalMediaDirs.firstOrNull()?.parentFile?.parentFile?.path
            ?: "/storage/emulated/0"
        val safeFolder = folder.ifBlank { APP_FOLDER }
        return "$root/Pictures/$safeFolder/$fileName"
    }

    /** Reconstructs "<storage>/<segments>" for a tree/document URI. */
    private fun treePath(uri: Uri): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        if (!DocumentsContract.isTreeUri(uri) && !DocumentsContract.isDocumentUri(this, uri)) {
            return null
        }
        val docId = DocumentsContract.getTreeDocumentId(uri) ?: return null
        val root = "/storage/emulated/0"
        val segments = docId.split(':').getOrNull(1)?.trim('/') ?: return null
        return "$root/$segments"
    }

    @Suppress("DEPRECATION")
    private fun legacyPicturesDir(): String =
        android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_PICTURES
        ).absolutePath

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FOLDER_REQUEST) return
        val result = pendingFolderResult ?: return
        pendingFolderResult = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Some providers do not hand out persistable grants; the session
            // grant is still enough for the export that follows.
        }
        val name = runCatching { DocumentFile.fromTreeUri(this, uri)?.name }.getOrNull()
        result.success(
            mapOf(
                "uri" to uri.toString(),
                "name" to (name ?: uri.lastPathSegment ?: ""),
                "path" to (runCatching { treePath(uri) }.getOrNull() ?: "")
            )
        )
    }
}
