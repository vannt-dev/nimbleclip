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
 * `Pictures`, a video to `Movies`, an audio file to `Music/NimbleClip`, or
 * each into a folder of the name chosen in Settings (`Pictures/<name>`...).
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
    fun save(
        context: Context,
        source: File,
        fileName: String,
        mimeType: String,
        kind: Kind,
        folder: String? = null,
    ): Uri {
        if (!source.isFile) throw IOException("File is missing: ${source.path}")
        val savedAt = System.currentTimeMillis()
        val album = albumFor(kind, folder)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveScoped(context, source, fileName, mimeType, kind, album, savedAt)
        } else {
            saveLegacy(context, source, fileName, mimeType, kind, album, savedAt)
        }
    }

    /**
     * The chosen folder, or the kind's default. The app checks the name when
     * it is chosen; a name that slipped through anyway is not used, so a file
     * never lands outside the folders the gallery and music apps read.
     */
    private fun albumFor(kind: Kind, folder: String?): String? {
        val name = folder?.trim().orEmpty()
        val usable = name.isNotEmpty() && name.length <= 40 && !name.startsWith(".") &&
            name.none { it in INVALID_FOLDER_CHARS || it.code < 0x20 || it.code == 0x7F }
        return if (usable) name else kind.defaultAlbum
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
        album: String?,
        savedAt: Long,
    ): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath(kind, album))
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
        album: String?,
        savedAt: Long,
    ): Uri {
        val root = Environment.getExternalStoragePublicDirectory(kind.directory)
        val directory = album?.let { File(root, it) } ?: root
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

    /**
     * Copies the lyrics file [source] beside the library's audio entry
     * [audioUri]: into the same folder, under the audio file's name with
     * `.lrc`, which is where music players look for lyrics. Returns the new
     * entry's URI.
     *
     * Blocks for the copy, so it must not run on the main thread. Throws when
     * the audio entry cannot be read or the library refuses the file.
     */
    fun saveLyricsBeside(context: Context, source: File, audioUri: Uri): Uri =
        saveBeside(context, source, audioUri, ".lrc", LYRICS_MIME_TYPE)

    /**
     * Copies the subtitles file [source] beside the gallery's video entry
     * [videoUri]: into the same folder, under the video file's name with
     * `.srt`, which is where video players look for subtitles. Returns the
     * new entry's URI.
     *
     * Blocks for the copy, so it must not run on the main thread. Throws when
     * the video entry cannot be read or the library refuses the file.
     */
    fun saveSubtitlesBeside(context: Context, source: File, videoUri: Uri): Uri =
        saveBeside(context, source, videoUri, ".srt", SUBTITLES_MIME_TYPE)

    private fun saveBeside(
        context: Context,
        source: File,
        mediaUri: Uri,
        extension: String,
        mimeType: String,
    ): Uri {
        if (!source.isFile) throw IOException("File is missing: ${source.path}")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveBesideScoped(context, source, mediaUri, extension, mimeType)
        } else {
            saveBesideLegacy(context, source, mediaUri, extension)
        }
    }

    private fun saveBesideScoped(
        context: Context,
        source: File,
        mediaUri: Uri,
        extension: String,
        mimeType: String,
    ): Uri {
        val resolver = context.contentResolver
        val columns = arrayOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        val (mediaName, folder) = resolver.query(mediaUri, columns, null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) to it.getString(1) else null
        } ?: throw IOException("The library entry is missing: $mediaUri")
        if (mediaName.isNullOrBlank() || folder.isNullOrBlank()) {
            throw IOException("The library entry has no name or folder: $mediaUri")
        }
        val sideName = sideName(mediaName, extension)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, sideName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(files, values)
            ?: throw IOException("The media library did not accept $sideName")
        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IOException("The entry for $sideName could not be opened")
            output.use { sink -> source.inputStream().use { it.copyTo(sink) } }
            val published = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, published, null, null)
            // The library may rename a file it accepts; one that no longer
            // matches the media file's name would not be found by players.
            val (savedName, savedFolder) = resolver.query(uri, columns, null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) to it.getString(1) else null
            } ?: throw IOException("The entry for $sideName could not be read back")
            if (savedName != sideName || savedFolder != folder) {
                throw IOException("$sideName was filed as $savedFolder$savedName")
            }
            return uri
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }

    /** Android 9 and older: written straight into the media file's folder. */
    @Suppress("DEPRECATION")
    private fun saveBesideLegacy(
        context: Context,
        source: File,
        mediaUri: Uri,
        extension: String,
    ): Uri {
        val columns = arrayOf(MediaStore.MediaColumns.DATA)
        val mediaPath = context.contentResolver.query(mediaUri, columns, null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: throw IOException("The library entry is missing: $mediaUri")
        val mediaFile = File(mediaPath)
        val directory = mediaFile.parentFile
            ?: throw IOException("The library entry has no folder: $mediaPath")
        val target = File(directory, sideName(mediaFile.name, extension))
        source.copyTo(target, overwrite = true)
        return Uri.fromFile(target)
    }

    /** `song.m4a` becomes `song.lrc`, `clip.mp4` becomes `clip.srt`. */
    private fun sideName(mediaName: String, extension: String): String =
        mediaName.substringBeforeLast('.', mediaName) + extension

    private fun relativePath(kind: Kind, album: String?): String =
        album?.let { "${kind.directory}/$it" } ?: kind.directory

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

    /** Characters a folder name may not hold, path separators among them. */
    private const val INVALID_FOLDER_CHARS = "/\\:*?\"<>|"

    /** The type music players and the media library know lyrics files by. */
    private const val LYRICS_MIME_TYPE = "application/lrc"

    /** The type the media library knows SubRip subtitles by. */
    private const val SUBTITLES_MIME_TYPE = "application/x-subrip"

    /** `MediaColumns.DATE_TAKEN` from Android 10; the same column name before. */
    private const val DATE_TAKEN = "datetaken"
}
