package com.vannt.nimbleclip

import android.system.Os
import androidx.exifinterface.media.ExifInterface
import java.io.FileDescriptor
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Writes the moment a file was saved into the file's own metadata, where the
 * media library reads its capture date (`DATE_TAKEN`) from.
 *
 * The library takes that column from the file only: from Android 11 an app
 * may not set it itself. A downloaded video usually carries no creation time
 * and a downloaded picture no EXIF date, so media pickers that sort by it,
 * WhatsApp's among them, listed the file under 1 January 1970.
 *
 * Works on the descriptor of the copy being added to the library, before it
 * is published; the app's own copy is left as it is. Best effort: a format it
 * cannot write (GIF, WebM, MKV, audio) is left unchanged.
 */
object CaptureDate {
    /** Seconds from 1904-01-01, the MP4 epoch, to 1970-01-01. */
    private const val MP4_EPOCH_OFFSET = 2_082_844_800L
    private const val MAX_BOXES = 4096

    /** Returns whether a date was written. Never throws. */
    fun stamp(fd: FileDescriptor, mimeType: String, millis: Long): Boolean = runCatching {
        when {
            mimeType in EXIF_WRITABLE -> stampExif(fd, millis)
            mimeType in MP4_FAMILY -> stampMp4(fd, millis)
            else -> false
        }
    }.getOrDefault(false)

    private val EXIF_WRITABLE = setOf("image/jpeg", "image/png", "image/webp")
    private val MP4_FAMILY = setOf("video/mp4", "video/quicktime", "video/3gpp")

    private fun stampExif(fd: FileDescriptor, millis: Long): Boolean {
        val exif = ExifInterface(fd)
        val date = Date(millis)
        val local = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).format(date)
        val offset = SimpleDateFormat("XXX", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }.format(date)
        exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, local)
        exif.setAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL, offset)
        exif.setAttribute(ExifInterface.TAG_DATETIME, local)
        exif.setAttribute(ExifInterface.TAG_OFFSET_TIME, offset)
        exif.saveAttributes()
        return true
    }

    /**
     * Sets the creation and modification time of the movie header (`mvhd`
     * inside `moov`), in place: the field widths do not change, so nothing
     * else in the file moves.
     */
    private fun stampMp4(fd: FileDescriptor, millis: Long): Boolean {
        val length = Os.fstat(fd).st_size
        val moov = findBox(fd, 0, length, "moov") ?: return false
        val mvhd = findBox(fd, moov.first, moov.second, "mvhd") ?: return false
        val version = read(fd, mvhd.first, 1)[0].toInt()
        val seconds = millis / 1000 + MP4_EPOCH_OFFSET
        val timesAt = mvhd.first + 4
        val times = if (version == 1) {
            ByteBuffer.allocate(16).putLong(seconds).putLong(seconds)
        } else {
            ByteBuffer.allocate(8).putInt(seconds.toInt()).putInt(seconds.toInt())
        }
        val bytes = times.array()
        if (timesAt + bytes.size > mvhd.second) return false
        Os.pwrite(fd, bytes, 0, bytes.size, timesAt)
        return true
    }

    /**
     * Finds the box of [type] among the boxes between [start] and [end], and
     * returns where its content starts and where the box ends.
     */
    private fun findBox(fd: FileDescriptor, start: Long, end: Long, type: String): Pair<Long, Long>? {
        var at = start
        var boxes = 0
        while (at + 8 <= end && boxes++ < MAX_BOXES) {
            val header = ByteBuffer.wrap(read(fd, at, 8))
            var size = header.int.toLong() and 0xFFFFFFFFL
            val name = String(header.array(), 4, 4, Charsets.ISO_8859_1)
            var headerSize = 8L
            if (size == 1L) {
                size = ByteBuffer.wrap(read(fd, at + 8, 8)).long
                headerSize = 16
            } else if (size == 0L) {
                size = end - at
            }
            if (size < headerSize || at + size > end) return null
            if (name == type) return (at + headerSize) to (at + size)
            at += size
        }
        return null
    }

    private fun read(fd: FileDescriptor, offset: Long, count: Int): ByteArray {
        val bytes = ByteArray(count)
        var done = 0
        while (done < count) {
            val n = Os.pread(fd, bytes, done, count - done, offset + done)
            if (n <= 0) throw java.io.EOFException("Unexpected end of file")
            done += n
        }
        return bytes
    }
}
