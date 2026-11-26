package com.vannt.nimbleclip

import android.content.Intent
import android.os.Bundle
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
        AppChannels.register(applicationContext, flutterEngine) {
            if (isFinishing || isDestroyed) null else this
        }
        QuickShareBridge.attach(flutterEngine, applicationContext)
    }

    /// The engine Quick download started with no screen, when there is one:
    /// opening the app then shows the downloads it is already working on
    /// instead of starting a second engine beside it.
    override fun getCachedEngineId(): String? =
        QuickShareBridge.cachedEngineId() ?: super.getCachedEngineId()

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
}
