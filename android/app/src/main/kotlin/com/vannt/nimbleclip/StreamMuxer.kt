package com.vannt.nimbleclip

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Joins a video-only and an audio-only MP4 into one MP4 without re-encoding.
 *
 * YouTube serves anything above 360p as separate picture and sound streams.
 * Both are already H.264 and AAC, which MP4 carries as they are, so this only
 * copies compressed samples from two [MediaExtractor]s into one [MediaMuxer]:
 * a 1080p clip takes seconds, and the picture is bit-for-bit what YouTube sent.
 *
 * Cancellation shares [SlideshowEncoder]'s registry, because both are started
 * and stopped through the same channel under the same render id.
 */
class StreamMuxer {
    data class Request(
        val videoPath: String,
        val audioPath: String,
        val outputPath: String,
        val renderId: String,
    )

    fun mux(request: Request, onProgress: (Double) -> Unit = {}): String {
        // A cancel sent while Dart was still fetching the streams stopped the
        // fetch, so this mux never ran to clear it. Left set, it would cancel
        // the retry of the same task the moment it started. Dart checks the
        // task is still wanted immediately before calling, which is what makes
        // clearing here safe.
        SlideshowEncoder.clearCancellation(request.renderId)
        val output = File(request.outputPath)
        output.parentFile?.mkdirs()
        val video = MediaExtractor()
        val audio = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false
        var succeeded = false
        try {
            video.setDataSource(request.videoPath)
            audio.setDataSource(request.audioPath)
            val videoFormat = selectTrack(video, "video/")
            val audioFormat = selectTrack(audio, "audio/")

            muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            videoFormat.rotation()?.let { muxer.setOrientationHint(it) }
            val videoTrack = muxer.addTrack(videoFormat)
            val audioTrack = muxer.addTrack(audioFormat)
            muxer.start()
            started = true

            val durationUs = videoFormat.durationUs() ?: audioFormat.durationUs() ?: 0L
            val buffer = ByteBuffer.allocate(
                maxOf(videoFormat.maxInputSize(), audioFormat.maxInputSize(), MIN_BUFFER_SIZE),
            )
            val info = MediaCodec.BufferInfo()
            var lastReported = -1.0

            // Interleaved by timestamp rather than track after track: MediaMuxer
            // buffers whatever arrives out of order, and feeding a whole video
            // track first would hold the entire audio track in memory.
            var videoDone = false
            var audioDone = false
            while (!videoDone || !audioDone) {
                if (SlideshowEncoder.isCancelled(request.renderId)) {
                    throw SlideshowCancelledException(request.renderId)
                }
                val takeVideo = !videoDone &&
                    (audioDone || video.sampleTime <= audio.sampleTime)
                val extractor = if (takeVideo) video else audio
                val track = if (takeVideo) videoTrack else audioTrack
                if (!copySample(extractor, muxer, track, buffer, info)) {
                    if (takeVideo) videoDone = true else audioDone = true
                    continue
                }
                if (takeVideo && durationUs > 0) {
                    val fraction = (info.presentationTimeUs.toDouble() / durationUs).coerceIn(0.0, 1.0)
                    if (fraction - lastReported >= PROGRESS_STEP) {
                        lastReported = fraction
                        onProgress(fraction)
                    }
                }
            }
            onProgress(1.0)
            succeeded = true
            return output.absolutePath
        } finally {
            SlideshowEncoder.clearCancellation(request.renderId)
            video.release()
            audio.release()
            try {
                if (started) muxer?.stop()
            } catch (error: IllegalStateException) {
                // A muxer stopped with no samples throws; the failure that got
                // us here is the one worth reporting.
                if (succeeded) throw error
            } finally {
                muxer?.release()
            }
            if (!succeeded) output.delete()
        }
    }

    /** Selects the first track whose MIME type starts with [prefix]. */
    private fun selectTrack(extractor: MediaExtractor, prefix: String): MediaFormat {
        for (index in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME).orEmpty().startsWith(prefix)) {
                extractor.selectTrack(index)
                return format
            }
        }
        throw SlideshowEncodeException("no ${prefix.trimEnd('/')} track in the input")
    }

    /** Copies one sample; false once [extractor] has none left. */
    private fun copySample(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        track: Int,
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
    ): Boolean {
        buffer.clear()
        val size = extractor.readSampleData(buffer, 0)
        if (size < 0) return false
        info.set(0, size, extractor.sampleTime, extractor.sampleFlags.toBufferFlags())
        muxer.writeSampleData(track, buffer, info)
        extractor.advance()
        return true
    }

    private fun Int.toBufferFlags(): Int {
        var flags = 0
        if (this and MediaExtractor.SAMPLE_FLAG_SYNC != 0) flags = flags or MediaCodec.BUFFER_FLAG_KEY_FRAME
        return flags
    }

    private fun MediaFormat.durationUs(): Long? =
        if (containsKey(MediaFormat.KEY_DURATION)) getLong(MediaFormat.KEY_DURATION) else null

    private fun MediaFormat.maxInputSize(): Int =
        if (containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) else 0

    private fun MediaFormat.rotation(): Int? =
        if (containsKey(MediaFormat.KEY_ROTATION)) getInteger(MediaFormat.KEY_ROTATION) else null

    private companion object {
        /** Large enough for a 1080p H.264 keyframe when the input omits a size. */
        const val MIN_BUFFER_SIZE = 4 shl 20
        const val PROGRESS_STEP = 0.01
    }
}
