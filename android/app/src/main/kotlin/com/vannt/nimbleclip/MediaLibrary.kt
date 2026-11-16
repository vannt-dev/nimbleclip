package com.vannt.nimbleclip

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import java.io.File
import java.io.IOException

/**
 * Adds a finished download to the device's shared media: a picture to
 * `Pictures`, a video to `Movies`, an audio file to `Music/NimbleClip`.
 *
 * Every copy carries the moment it was saved as its capture date, written into
 * the file's metadata ([CaptureDate]): media pickers such as WhatsApp's sort by
 * that date, and a downloaded file without one was listed under 1 January 1970,
 * far below the recent items.
 *
 * The file is copied, not moved: the app keeps its own copy for the download
 * list until the user chooses to remove it.
 */
object MediaLibrary {
    enum class Kind(val directory: String, val defaultAlbum: String?) {
        IMAGE(Environment.DIRECTORY_PICTURES, null),
        VIDEO(Environment.DIRECTORY_MOVIES, null),
        AUDIO(Environment.DIRECTORY_MUSIC, "NimbleClip");

        @Suppress("DEPRECATION")
        val legacyCollection: Uri
            get() = when (this) {
                IMAGE -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                VIDEO -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                AUDIO -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }

        fun collection(): Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (this) {
                IMAGE -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                VIDEO -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                AUDIO -> MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
        } else {
            legacyCollection
        }
    }

    /**
     * Copies [source] into the library and returns the new entry's URI.
     *
     * Blocks for the length of the copy, so it must not run on the main
     * thread. Throws when the file cannot be read or the library refuses it;
     * nothing is left behind in that case.
     */
    fun save(context: Context, source: File, fileName: String, mimeType: String, kind: Kind): Uri {
        if (!source.isFile) throw IOException("File is missing: ${source.path}")
        val savedAt = System.currentTimeMillis()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveScoped(context, source, fileName, mimeType, kind, savedAt)
        } else {
            saveLegacy(context, source, fileName, mimeType, kind, savedAt)
        }
    }

    /**
     * Android 10 and later: the entry is created first and hidden from other
     * apps (`IS_PENDING`) until the bytes are all there. Needs no permission,
     * because an app may always add files of its own.
     */
    private fun saveScoped(
        context: Context,
        source: File,
        fileName: String,
        mimeType: String,
        kind: Kind,
        savedAt: Long,
    ): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath(kind))
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(kind.collection(), values)
            ?: throw IOException("The media library did not accept $fileName")
        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IOException("The media library entry could not be opened")
            output.use { sink -> source.inputStream().use { it.copyTo(sink) } }
            // Publishing scans the file and takes the capture date from it.
            resolver.openFileDescriptor(uri, "rw")?.use {
                CaptureDate.stamp(it.fileDescriptor, mimeType, savedAt)
            }
            val published = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, published, null, null)
            return uri
        } catch (error: Exception) {
            // A half-written entry would sit in the library as a broken file.
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }

    /**
     * Android 9 and older have no pending entries or relative paths: the file
     * is written to the public folder and then registered by its path. This
     * relies on the storage permission the app asks for on these versions.
     */
    @Suppress("DEPRECATION")
    private fun saveLegacy(
        context: Context,
        source: File,
        fileName: String,
        mimeType: String,
        kind: Kind,
        savedAt: Long,
    ): Uri {
        val root = Environment.getExternalStoragePublicDirectory(kind.directory)
        val directory = kind.defaultAlbum?.let { File(root, it) } ?: root
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("The ${kind.directory} folder could not be created")
        }
        val target = uniqueFile(directory, fileName)
        try {
            source.inputStream().use { input ->
                target.outputStream().use { input.copyTo(it) }
            }
            ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_READ_WRITE).use {
                CaptureDate.stamp(it.fileDescriptor, mimeType, savedAt)
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, target.name)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.DATA, target.absolutePath)
                // Before Android 10 only pictures and videos have the column.
                if (kind != Kind.AUDIO) put(DATE_TAKEN, savedAt)
            }
            return context.contentResolver.insert(kind.legacyCollection, values)
                ?: throw IOException("The media library did not accept ${target.name}")
        } catch (error: Exception) {
            runCatching { target.delete() }
            throw error
        }
    }

    private fun relativePath(kind: Kind): String =
        kind.defaultAlbum?.let { "${kind.directory}/$it" } ?: kind.directory

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

    /** `MediaColumns.DATE_TAKEN` from Android 10; the same column name before. */
    private const val DATE_TAKEN = "datetaken"
}
