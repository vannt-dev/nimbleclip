package com.vannt.nimbleclip

/*
 * The Android encoders of the public core: the names MainActivity is written
 * against, with nothing behind them.
 *
 * Rendering a slideshow, joining a video's picture and sound, decrypting a
 * stream's segments and converting audio to MP3 are done by the full core,
 * which is not part of this repository. The public core's extractor never
 * offers a download that needs any of them, so these are reached only by
 * Settings -> Save audio as MP3, which then keeps the file as it was fetched.
 */

private const val NOT_HERE = "not part of the public core"

class SlideshowEncodeException(message: String, cause: Throwable? = null) :
    Exception(message, cause)

class SlideshowCancelledException(renderId: String) :
    Exception("slideshow render cancelled: $renderId")

class SlideshowEncoder {
    data class Request(
        val imagePaths: List<String>,
        val audioPath: String?,
        val perImageMs: Int,
        val width: Int,
        val height: Int,
        val outputPath: String,
        val renderId: String,
    )

    data class Result(val filePath: String, val audioSkipped: Boolean)

    @Suppress("UNUSED_PARAMETER")
    fun encode(request: Request, onProgress: (Double) -> Unit = {}): Result =
        throw SlideshowEncodeException(NOT_HERE)

    @Suppress("UNUSED_PARAMETER")
    fun probe(path: String): Map<String, Any?> = throw SlideshowEncodeException(NOT_HERE)

    @Suppress("UNUSED_PARAMETER")
    fun frameColorAt(path: String, atMs: Int): Map<String, Any?> =
        throw SlideshowEncodeException(NOT_HERE)

    companion object {
        @Suppress("UNUSED_PARAMETER")
        fun cancel(renderId: String) {
        }
    }
}

class StreamMuxer {
    data class Request(
        val videoPath: String,
        val audioPath: String,
        val outputPath: String,
        val renderId: String,
        val audioOptional: Boolean = false,
    )

    @Suppress("UNUSED_PARAMETER")
    fun mux(request: Request, onProgress: (Double) -> Unit = {}): String =
        throw SlideshowEncodeException(NOT_HERE)

    companion object {
        /** Nothing is joined in the public core. */
        const val canMergeStreams = false
    }
}

object SegmentCipher {
    @Suppress("UNUSED_PARAMETER")
    fun decrypt(sourcePath: String, outputPath: String, key: ByteArray, iv: ByteArray): String =
        throw SlideshowEncodeException(NOT_HERE)
}

class Mp3TranscodeException(message: String, cause: Throwable? = null) : Exception(message, cause)

class Mp3CancelledException(jobId: String) : Exception("mp3 conversion cancelled: $jobId")

class Mp3Transcoder {
    data class Request(
        val sourcePath: String,
        val outputPath: String,
        val jobId: String,
    )

    @Suppress("UNUSED_PARAMETER")
    fun transcode(request: Request, onProgress: (Double) -> Unit = {}): String =
        throw Mp3TranscodeException(NOT_HERE)

    companion object {
        @Suppress("UNUSED_PARAMETER")
        fun cancel(jobId: String) {
        }
    }
}
