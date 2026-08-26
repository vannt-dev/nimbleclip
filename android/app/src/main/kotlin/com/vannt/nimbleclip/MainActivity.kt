package com.vannt.nimbleclip

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var pendingSharedText: String? = null
    private var sharedTextSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        publishShareTarget()
    }

    /// A long-lived dynamic shortcut carrying the share-target category is what
    /// puts NimbleClip in the top Direct Share row of the system share sheet.
    /// The declaration in res/xml/shortcuts.xml alone is not enough: the
    /// framework only surfaces targets that are backed by a pushed shortcut.
    private fun publishShareTarget() {
        try {
            val shortcut = ShortcutInfoCompat.Builder(this, SHARE_SHORTCUT_ID)
                .setShortLabel(getString(R.string.share_target_label))
                .setLongLived(true)
                .setIcon(IconCompat.createWithResource(this, R.mipmap.ic_launcher))
                .setCategories(setOf(SHARE_TARGET_CATEGORY))
                .setIntent(
                    Intent(this, MainActivity::class.java).setAction(Intent.ACTION_MAIN),
                )
                .build()
            ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)
        } catch (error: Exception) {
            // Direct Share is a ranking nicety; the manifest SEND filter keeps
            // the app reachable from the share sheet either way.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        acceptSharedIntent(intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.vannt.nimbleclip/shared_intent",
        ).setMethodCallHandler { call, result ->
            if (call.method == "consumeSharedText") {
                result.success(pendingSharedText)
                pendingSharedText = null
            } else {
                result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.vannt.nimbleclip/shared_intent_events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sharedTextSink = events
            }

            override fun onCancel(arguments: Any?) {
                sharedTextSink = null
            }
        })
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptSharedIntent(intent)
    }

    private fun acceptSharedIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || !intent.type.orEmpty().startsWith("text/")) {
            return
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        if (text.isNullOrBlank()) return
        pendingSharedText = text
        sharedTextSink?.success(text)
    }

    companion object {
        private const val SHARE_SHORTCUT_ID = "share_link"
        private const val SHARE_TARGET_CATEGORY =
            "com.vannt.nimbleclip.category.SHARE_LINK"
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
