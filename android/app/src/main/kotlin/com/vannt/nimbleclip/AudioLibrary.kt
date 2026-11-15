package com.vannt.nimbleclip

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException

/**
 * Adds a finished audio download to the device's shared Music library, under
 * `Music/NimbleClip`, where music players and file managers look for it.
 *
 * The gallery plugin covers pictures and videos only, so audio goes through
 * MediaStore directly. The file is copied, not moved: the app keeps its own
 * copy for the download list until the user chooses to remove it.
 */
object AudioLibrary {
    private const val ALBUM = "NimbleClip"

    /**
     * Copies [source] into the Music library and returns the new entry's URI.
     *
     * Blocks for the length of the copy, so it must not run on the main
     * thread. Throws when the file cannot be read or the library refuses it;
     * nothing is left behind in that case.
     */
    fun save(context: Context, source: File, fileName: String, mimeType: String): Uri {
        if (!source.isFile) throw IOException("Audio file is missing: ${source.path}")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveScoped(context, source, fileName, mimeType)
        } else {
            saveLegacy(context, source, fileName, mimeType)
        }
    }

    /**
     * Android 10 and later: the entry is created first and hidden from other
     * apps (`IS_PENDING`) until the bytes are all there. Needs no permission,
     * because an app may always add files of its own.
     */
    private fun saveScoped(context: Context, source: File, fileName: String, mimeType: String): Uri {
        val resolver = context.contentResolver
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${Environment.DIRECTORY_MUSIC}/$ALBUM",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("The Music library did not accept $fileName")
        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IOException("The Music library entry could not be opened")
            output.use { sink -> source.inputStream().use { it.copyTo(sink) } }
            val published = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, published, null, null)
            return uri
        } catch (error: Exception) {
            // A half-written entry would sit in the library as a broken track.
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }

    /**
     * Android 9 and older have no pending entries or relative paths: the file
     * is written to the public Music folder and then registered by its path.
     * This is what the gallery plugin does for videos on these versions, and
     * it relies on the same storage permission.
     */
    @Suppress("DEPRECATION")
    private fun saveLegacy(context: Context, source: File, fileName: String, mimeType: String): Uri {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            ALBUM,
        )
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("The Music folder could not be created")
        }
        val target = uniqueFile(directory, fileName)
        try {
            source.inputStream().use { input ->
                target.outputStream().use { input.copyTo(it) }
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, target.name)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.DATA, target.absolutePath)
            }
            return context.contentResolver.insert(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                values,
            ) ?: throw IOException("The Music library did not accept ${target.name}")
        } catch (error: Exception) {
            runCatching { target.delete() }
            throw error
        }
    }

    /** `name.mp3`, or `name (1).mp3` and so on when that is already taken. */
    private fun uniqueFile(directory: File, fileName: String): File {
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var candidate = File(directory, fileName)
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, "$base ($index)$extension")
            index++
        }
        return candidate
    }
}
