package com.vannt.nimbleclip

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.vannt.nimbleclip/media_store",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "mediaExists", "findMediaUri" -> {
                        val fileName = call.argument<String>("fileName")
                        val isImage = call.argument<Boolean>("isImage") ?: false
                        if (fileName.isNullOrBlank()) {
                            result.success(if (call.method == "mediaExists") false else null)
                            return@setMethodCallHandler
                        }
                        val uri = findMediaUri(fileName, isImage)
                        result.success(if (call.method == "mediaExists") uri != null else uri?.toString())
                    }
                    "openMediaUri" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, contentResolver.getType(uri) ?: "*/*")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                    }
                    "shareMediaUri" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = contentResolver.getType(uri) ?: "*/*"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                call.argument<String>("text")?.let {
                                    putExtra(Intent.EXTRA_TEXT, it)
                                }
                                clipData = ClipData.newUri(contentResolver, "media", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(intent, null))
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("media_query_failed", error.message, null)
            }
        }
    }

    private fun findMediaUri(fileName: String, isImage: Boolean): Uri? {
        val collection = if (isImage) {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
        val dotIndex = fileName.lastIndexOf('.')
        val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        return contentResolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? OR " +
                "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
            arrayOf(fileName, "$baseName%$extension"),
            "${MediaStore.MediaColumns.DATE_ADDED} DESC",
        ).use { cursor ->
            if (cursor?.moveToFirst() != true) return@use null
            Uri.withAppendedPath(collection, cursor.getLong(0).toString())
        }
    }
}
