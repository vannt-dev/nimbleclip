package com.vannt.nimbleclip

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
            if (call.method != "mediaExists") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val fileName = call.argument<String>("fileName")
            val isImage = call.argument<Boolean>("isImage") ?: false
            if (fileName.isNullOrBlank()) {
                result.success(false)
                return@setMethodCallHandler
            }

            try {
                val collection = if (isImage) {
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                } else {
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                }
                val dotIndex = fileName.lastIndexOf('.')
                val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
                val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
                contentResolver.query(
                    collection,
                    arrayOf(MediaStore.MediaColumns._ID),
                    "${MediaStore.MediaColumns.DISPLAY_NAME} = ? OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
                    arrayOf(fileName, "$baseName%$extension"),
                    null,
                ).use { cursor -> result.success(cursor?.moveToFirst() == true) }
            } catch (error: Exception) {
                result.error("media_query_failed", error.message, null)
            }
        }
    }
}
