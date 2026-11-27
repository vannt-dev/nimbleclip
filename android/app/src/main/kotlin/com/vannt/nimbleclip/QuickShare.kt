package com.vannt.nimbleclip

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * The "Quick download" entry of the share sheet.
 *
 * Shows nothing: it hands the shared text to the app's engine and closes, so
 * the app the link was shared from stays on screen. It is off until the user
 * turns Quick download on in Settings, which enables this component.
 */
class QuickDownloadActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent
            ?.takeIf { it.action == Intent.ACTION_SEND }
            ?.getStringExtra(Intent.EXTRA_TEXT)
            ?.trim()
        if (!text.isNullOrBlank()) {
            // Started here, while this activity is on screen: the system
            // refuses a foreground service started once the app is behind
            // another one, and finding the video takes a few seconds.
            KeepAliveService.start(
                applicationContext,
                getString(R.string.quick_download_title),
                getString(R.string.quick_download_preparing),
                QuickShareBridge.KEEP_ALIVE_HOLDER,
            )
            QuickShareBridge.deliver(applicationContext, text)
        }
        finish()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }
}

/**
 * Carries links from [QuickDownloadActivity] to the app's Dart side.
 *
 * Whichever engine is running takes them: the one behind the app's screen, or,
 * when the app is not running, one started here with no screen. That engine is
 * kept so that opening the app afterwards shows the same downloads.
 */
object QuickShareBridge {
    const val KEEP_ALIVE_HOLDER = "quick_share"
    private const val ENGINE_ID = "nimbleclip_quick_share"
    private const val METHODS = "com.vannt.nimbleclip/quick_share"
    private const val EVENTS = "com.vannt.nimbleclip/quick_share_events"

    private val pending = ArrayDeque<String>()
    private val engines = mutableListOf<FlutterEngine>()
    private var sink: EventChannel.EventSink? = null
    private var sinkEngine: FlutterEngine? = null

    fun cachedEngineId(): String? =
        if (FlutterEngineCache.getInstance().contains(ENGINE_ID)) ENGINE_ID else null

    fun deliver(context: Context, text: String) {
        val live = sink
        if (live != null) {
            live.success(text)
            return
        }
        pending.addLast(text)
        // An engine that is still starting asks for what is pending.
        if (engines.isEmpty()) startEngine(context.applicationContext)
    }

    fun attach(engine: FlutterEngine, context: Context) {
        if (engines.none { it === engine }) {
            engines.add(engine)
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}

                override fun onEngineWillDestroy() {
                    engines.removeAll { it === engine }
                    if (sinkEngine === engine) {
                        sink = null
                        sinkEngine = null
                    }
                }
            })
        }
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePending" -> {
                    result.success(pending.toList())
                    pending.clear()
                }
                "setTargetEnabled" -> {
                    setTargetEnabled(context, call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "showMessage" -> {
                    val message = call.argument<String>("message")
                    if (!message.isNullOrBlank()) {
                        Toast.makeText(context, message, Toast.LENGTH_LONG).show()
                    }
                    result.success(null)
                }
                "releaseKeepAlive" -> {
                    KeepAliveService.stop(context, KEEP_ALIVE_HOLDER)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                sinkEngine = engine
            }

            override fun onCancel(arguments: Any?) {
                if (sinkEngine === engine) {
                    sink = null
                    sinkEngine = null
                }
            }
        })
    }

    /// The app's normal Dart entry point, with no screen attached. The app's
    /// downloads, settings and history live there exactly as when it is open.
    private fun startEngine(context: Context) {
        val engine = FlutterEngine(context)
        engine.localizationPlugin.sendLocalesToFlutter(context.resources.configuration)
        AppChannels.register(context, engine) { null }
        attach(engine, context)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
    }

    private fun setTargetEnabled(context: Context, enabled: Boolean) {
        val component = ComponentName(context, QuickDownloadActivity::class.java)
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        val packageManager = context.packageManager
        if (packageManager.getComponentEnabledSetting(component) == state) return
        packageManager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
    }
}
