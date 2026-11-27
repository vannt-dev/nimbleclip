package com.vannt.nimbleclip

import android.app.Activity
import android.app.Notification
import android.app.NotificationManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * The app's own platform channels: keeping the process alive, the media
 * library, joining and rendering, audio conversion.
 *
 * Registered on every Flutter engine the app runs, not only the one an
 * activity owns: a link sent to Quick download starts the app's engine with no
 * screen at all, and its download still has to be joined, saved to the gallery
 * and so on. [activity] is asked each time for the screen to open or share a
 * file from; without one the system is asked from the application.
 */
object AppChannels {
    private const val MAX_CAUSE_DEPTH = 32

    fun register(context: Context, engine: FlutterEngine, activity: () -> Activity?) {
        val messenger = engine.dartExecutor.binaryMessenger
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, "com.vannt.nimbleclip/keep_alive").setMethodCallHandler { call, result ->
            val holder = call.argument<String>("holder") ?: KeepAliveService.DEFAULT_HOLDER
            when (call.method) {
                "start" -> result.success(
                    KeepAliveService.start(
                        context,
                        call.argument<String>("title") ?: "NimbleClip",
                        call.argument<String>("text") ?: "",
                        holder,
                    ),
                )
                "stop" -> {
                    KeepAliveService.stop(context, holder)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "com.vannt.nimbleclip/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "cancelByText" -> {
                    val text = call.argument<String>("text")
                    if (!text.isNullOrEmpty()) {
                        val sweep = Runnable { cancelNotificationsWithText(context, text) }
                        sweep.run()
                        // The download library posts at most every 300 ms, so
                        // a notice can land just after the first sweep.
                        main.postDelayed(sweep, 1500)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "com.vannt.nimbleclip/media_store").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "mediaExists", "findMediaUri" -> {
                        val fileName = call.argument<String>("fileName")
                        val isImage = call.argument<Boolean>("isImage") ?: false
                        val isAudio = call.argument<Boolean>("isAudio") ?: false
                        if (fileName.isNullOrBlank()) {
                            result.success(if (call.method == "mediaExists") false else null)
                            return@setMethodCallHandler
                        }
                        val uri = findMediaUri(context, fileName, isImage, isAudio)
                        result.success(if (call.method == "mediaExists") uri != null else uri?.toString())
                    }
                    "saveMedia" -> {
                        val path = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType")
                        val kind = when (call.argument<String>("kind")) {
                            "image" -> MediaLibrary.Kind.IMAGE
                            "video" -> MediaLibrary.Kind.VIDEO
                            "audio" -> MediaLibrary.Kind.AUDIO
                            else -> null
                        }
                        val folder = call.argument<String>("folder")
                        if (path.isNullOrBlank() || fileName.isNullOrBlank() ||
                            mimeType.isNullOrBlank() || kind == null
                        ) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        // A video is megabytes; copying it on the platform
                        // thread would freeze the UI for as long as it takes.
                        Thread {
                            try {
                                val uri = MediaLibrary.save(
                                    context,
                                    java.io.File(path),
                                    fileName,
                                    mimeType,
                                    kind,
                                    folder,
                                )
                                main.post { result.success(uri.toString()) }
                            } catch (error: Exception) {
                                main.post {
                                    result.error("media_save_failed", error.message, null)
                                }
                            }
                        }.start()
                    }
                    "saveLyricsBeside" -> {
                        val path = call.argument<String>("path")
                        val audioUri = call.argument<String>("audioUri")?.let(Uri::parse)
                        if (path.isNullOrBlank() || audioUri == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val uri = MediaLibrary.saveLyricsBeside(
                                    context,
                                    java.io.File(path),
                                    audioUri,
                                )
                                main.post { result.success(uri.toString()) }
                            } catch (error: Exception) {
                                main.post {
                                    result.error("lyrics_save_failed", error.message, null)
                                }
                            }
                        }.start()
                    }
                    "saveSubtitlesBeside" -> {
                        val path = call.argument<String>("path")
                        val videoUri = call.argument<String>("videoUri")?.let(Uri::parse)
                        if (path.isNullOrBlank() || videoUri == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val uri = MediaLibrary.saveSubtitlesBeside(
                                    context,
                                    java.io.File(path),
                                    videoUri,
                                )
                                main.post { result.success(uri.toString()) }
                            } catch (error: Exception) {
                                main.post {
                                    result.error("subtitles_save_failed", error.message, null)
                                }
                            }
                        }.start()
                    }
                    "openMediaUri" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, context.contentResolver.getType(uri) ?: "*/*")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            launch(context, activity(), intent)
                            result.success(true)
                        }
                    }
                    "shareMediaUri" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null) {
                            result.success(false)
                        } else {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = context.contentResolver.getType(uri) ?: "*/*"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                call.argument<String>("text")?.let {
                                    putExtra(Intent.EXTRA_TEXT, it)
                                }
                                clipData = ClipData.newUri(context.contentResolver, "media", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            launch(context, activity(), Intent.createChooser(intent, null))
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("media_query_failed", error.message, null)
            }
        }
        val slideshowChannel = MethodChannel(messenger, "com.vannt.nimbleclip/slideshow")
        slideshowChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Answered on the platform thread: it only sets a flag, and a
                // cancel that queued behind the render it is cancelling would
                // never arrive in time to stop anything.
                "cancel" -> {
                    SlideshowEncoder.cancel(call.argument<String>("renderId").orEmpty())
                    result.success(null)
                }
                // Whether this device can join a video's separate picture and
                // sound; the core knows which systems cannot.
                "canMergeStreams" -> result.success(StreamMuxer.canMergeStreams)
                "render", "mux", "probe", "frameColorAt", "decryptSegment" -> {
                    // A slideshow encode runs for seconds; on the platform
                    // thread that freezes the UI and trips the ANR watchdog.
                    // The MethodChannel.Result must still be completed on the
                    // main thread, hence the hand-back through `main`.
                    Thread {
                        try {
                            val encoder = SlideshowEncoder()
                            val payload: Any = when (call.method) {
                                "probe" -> encoder.probe(call.argument<String>("path")!!)
                                "decryptSegment" -> mapOf(
                                    "filePath" to SegmentCipher.decrypt(
                                        sourcePath = call.argument<String>("sourcePath")!!,
                                        outputPath = call.argument<String>("outputPath")!!,
                                        key = call.argument<ByteArray>("key")!!,
                                        iv = call.argument<ByteArray>("iv")!!,
                                    ),
                                )
                                "mux" -> {
                                    val renderId = call.argument<String>("renderId").orEmpty()
                                    val filePath = StreamMuxer().mux(
                                        StreamMuxer.Request(
                                            videoPath = call.argument<String>("videoPath")!!,
                                            audioPath = call.argument<String>("audioPath")!!,
                                            outputPath = call.argument<String>("outputPath")!!,
                                            renderId = renderId,
                                            audioOptional = call.argument<Boolean>("audioOptional") ?: false,
                                            audioOnly = call.argument<Boolean>("audioOnly") ?: false,
                                        ),
                                    ) { progress ->
                                        main.post {
                                            slideshowChannel.invokeMethod(
                                                "progress",
                                                mapOf(
                                                    "renderId" to renderId,
                                                    "progress" to progress,
                                                ),
                                            )
                                        }
                                    }
                                    mapOf("filePath" to filePath)
                                }
                                "frameColorAt" -> encoder.frameColorAt(
                                    call.argument<String>("path")!!,
                                    call.argument<Int>("atMs") ?: 0,
                                )
                                else -> {
                                    val renderId = call.argument<String>("renderId").orEmpty()
                                    val encoded = encoder.encode(
                                        SlideshowEncoder.Request(
                                            imagePaths = call.argument<List<String>>("imagePaths").orEmpty(),
                                            audioPath = call.argument<String>("audioPath"),
                                            perImageMs = call.argument<Int>("perImageMs") ?: 3000,
                                            width = call.argument<Int>("width") ?: 1080,
                                            height = call.argument<Int>("height") ?: 1920,
                                            outputPath = call.argument<String>("outputPath")!!,
                                            renderId = renderId,
                                        ),
                                    ) { progress ->
                                        // Dart may only be addressed from the
                                        // main thread; this callback arrives on
                                        // the encode worker.
                                        main.post {
                                            slideshowChannel.invokeMethod(
                                                "progress",
                                                mapOf(
                                                    "renderId" to renderId,
                                                    "progress" to progress,
                                                ),
                                            )
                                        }
                                    }
                                    mapOf(
                                        "filePath" to encoded.filePath,
                                        "audioSkipped" to encoded.audioSkipped,
                                    )
                                }
                            }
                            main.post { result.success(payload) }
                        } catch (error: Throwable) {
                            // Throwable, not Exception: decoding a large image
                            // can raise OutOfMemoryError, which is an Error. If
                            // it escaped here it would kill this worker thread
                            // with the Result never completed, crashing the app
                            // and leaving the Dart future pending forever.
                            val code = when {
                                error is SlideshowCancelledException -> "cancelled"
                                isOutOfSpace(error) -> "out_of_space"
                                else -> "encode_failed"
                            }
                            val message = error.message ?: error.toString()
                            main.post { result.error(code, message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        val audioChannel = MethodChannel(messenger, "com.vannt.nimbleclip/audio")
        audioChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // On the platform thread for the same reason as the slideshow
                // cancel: it must not queue behind the job it is stopping.
                "cancel" -> {
                    Mp3Transcoder.cancel(call.argument<String>("jobId").orEmpty())
                    result.success(null)
                }
                "toMp3" -> {
                    val jobId = call.argument<String>("jobId").orEmpty()
                    val request = Mp3Transcoder.Request(
                        sourcePath = call.argument<String>("sourcePath")!!,
                        outputPath = call.argument<String>("outputPath")!!,
                        jobId = jobId,
                    )
                    Thread {
                        try {
                            val filePath = Mp3Transcoder().transcode(request) { progress ->
                                main.post {
                                    audioChannel.invokeMethod(
                                        "progress",
                                        mapOf("jobId" to jobId, "progress" to progress),
                                    )
                                }
                            }
                            main.post { result.success(mapOf("filePath" to filePath)) }
                        } catch (error: Throwable) {
                            // Throwable for the same reason as above; it also
                            // covers a library that failed to load.
                            val code = when {
                                error is Mp3CancelledException -> "cancelled"
                                isOutOfSpace(error) -> "out_of_space"
                                else -> "convert_failed"
                            }
                            val message = error.message ?: error.toString()
                            main.post { result.error(code, message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Removes this app's notifications whose body is exactly [text]. */
    private fun cancelNotificationsWithText(context: Context, text: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        try {
            manager.activeNotifications
                .filter {
                    it.notification.extras
                        .getCharSequence(Notification.EXTRA_TEXT)
                        ?.toString() == text
                }
                .forEach { manager.cancel(it.tag, it.id) }
        } catch (_: RuntimeException) {
            // A notice left in place is only cosmetic.
        }
    }

    /// From the screen when there is one; from the application otherwise,
    /// which the system only accepts as the start of a new task.
    private fun launch(context: Context, activity: Activity?, intent: Intent) {
        if (activity != null) {
            activity.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /**
     * A full disk surfaces as an IOException from the muxer rather than a
     * distinct type, so the message is the only thing left to match on.
     *
     * The walk is bounded and remembers what it has seen: a self-referencing
     * or mutually-referencing cause chain is legal, and some wrapping
     * libraries produce one, which would spin this worker thread forever.
     */
    private fun isOutOfSpace(error: Throwable?): Boolean {
        val seen = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Throwable, Boolean>())
        var current = error
        var depth = 0
        while (current != null && depth++ < MAX_CAUSE_DEPTH && seen.add(current)) {
            if (current is IOException) {
                val message = current.message.orEmpty().lowercase()
                if (message.contains("space") || message.contains("enospc")) return true
            }
            current = current.cause
        }
        return false
    }

    private fun findMediaUri(context: Context, fileName: String, isImage: Boolean, isAudio: Boolean): Uri? {
        val collection = when {
            isAudio -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            isImage -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
        val dotIndex = fileName.lastIndexOf('.')
        val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        return context.contentResolver.query(
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
