package com.vannt.nimbleclip

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap

/** The audio could not be turned into an MP3; the message is for the log. */
class Mp3TranscodeException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** Raised when [Mp3Transcoder.cancel] was called for a job still running. */
class Mp3CancelledException(jobId: String) : Exception("mp3 conversion cancelled: $jobId")

/**
 * Re-encodes the sound of a downloaded file (M4A, WebM, MP4...) as an MP3.
 *
 * The platform decodes: [MediaExtractor] reads the first audio track and a
 * [MediaCodec] decoder turns it into PCM, whatever the source codec is. LAME
 * ([Mp3Encoder]) encodes that PCM at a constant bitrate picked from the
 * source's own, so a 128 kbps download does not become a 320 kbps file that
 * is larger and no better.
 */
class Mp3Transcoder {
    data class Request(
        val sourcePath: String,
        val outputPath: String,
        /** Names this job so [cancel] can address it. */
        val jobId: String,
    )

    fun transcode(request: Request, onProgress: (Double) -> Unit = {}): String {
        cancelledJobs.remove(request.jobId)
        val output = File(request.outputPath)
        output.parentFile?.mkdirs()
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder = 0L
        var succeeded = false
        try {
            extractor.setDataSource(request.sourcePath)
            val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME).orEmpty().startsWith("audio/")
            } ?: throw Mp3TranscodeException("no audio track in the input")
            extractor.selectTrack(trackIndex)
            val inputFormat = extractor.getTrackFormat(trackIndex)
            val durationUs = inputFormat.longOrNull(MediaFormat.KEY_DURATION) ?: 0L
            val kbps = targetKbps(inputFormat, File(request.sourcePath).length(), durationUs)

            decoder = MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder.configure(inputFormat, null, null, 0)
            decoder.start()

            BufferedOutputStream(FileOutputStream(output)).use { sink ->
                val info = MediaCodec.BufferInfo()
                var pcm = PcmLayout.from(decoder.outputFormat)
                var mp3 = ByteArray(0)
                var samples = ShortArray(0)
                var inputDone = false
                var outputDone = false
                var lastReported = -1.0

                while (!outputDone) {
                    if (cancelledJobs.contains(request.jobId)) throw Mp3CancelledException(request.jobId)

                    if (!inputDone) {
                        val inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                        if (inputIndex >= 0) {
                            val buffer = decoder.getInputBuffer(inputIndex)!!
                            val size = extractor.readSampleData(buffer, 0)
                            if (size < 0) {
                                decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                decoder.queueInputBuffer(inputIndex, 0, size, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }

                    val outputIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                    if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        // The decoder only knows the real layout once it has read
                        // the stream: HE-AAC, for one, doubles the sample rate.
                        pcm = PcmLayout.from(decoder.outputFormat)
                    } else if (outputIndex >= 0) {
                        if (info.size > 0) {
                            val buffer = decoder.getOutputBuffer(outputIndex)!!
                            buffer.position(info.offset).limit(info.offset + info.size)
                            val frames = pcm.frames(info.size)
                            val outChannels = pcm.outputChannels
                            if (samples.size < frames * outChannels) samples = ShortArray(frames * outChannels)
                            pcm.read(buffer.order(ByteOrder.nativeOrder()), frames, samples)

                            if (encoder == 0L) {
                                encoder = Mp3Encoder.nativeOpen(pcm.sampleRate, outChannels, kbps)
                                if (encoder == 0L) {
                                    throw Mp3TranscodeException(
                                        "LAME rejected ${pcm.sampleRate} Hz, $outChannels channels, $kbps kbps",
                                    )
                                }
                            }
                            val capacity = Mp3Encoder.outputCapacity(frames)
                            if (mp3.size < capacity) mp3 = ByteArray(capacity)
                            val written = Mp3Encoder.nativeEncode(encoder, samples, frames, outChannels, mp3)
                            if (written < 0) throw Mp3TranscodeException("LAME failed to encode ($written)")
                            sink.write(mp3, 0, written)

                            if (durationUs > 0) {
                                val fraction = (info.presentationTimeUs.toDouble() / durationUs).coerceIn(0.0, 1.0)
                                if (fraction - lastReported >= PROGRESS_STEP) {
                                    lastReported = fraction
                                    onProgress(fraction)
                                }
                            }
                        }
                        decoder.releaseOutputBuffer(outputIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }

                if (encoder == 0L) throw Mp3TranscodeException("the audio track decoded to nothing")
                val tail = ByteArray(Mp3Encoder.FLUSH_BYTES)
                val written = Mp3Encoder.nativeFlush(encoder, tail)
                if (written < 0) throw Mp3TranscodeException("LAME failed to flush ($written)")
                sink.write(tail, 0, written)
            }
            onProgress(1.0)
            succeeded = true
            return output.absolutePath
        } catch (error: Mp3TranscodeException) {
            throw error
        } catch (error: Mp3CancelledException) {
            throw error
        } catch (error: java.io.IOException) {
            // Kept as it is: a full disk is told apart by its message.
            throw error
        } catch (error: Exception) {
            // MediaCodec and MediaExtractor report an unreadable file with a
            // range of runtime exceptions; to the caller they are one thing.
            throw Mp3TranscodeException(error.message ?: error.toString(), error)
        } finally {
            cancelledJobs.remove(request.jobId)
            if (encoder != 0L) Mp3Encoder.nativeClose(encoder)
            try {
                decoder?.stop()
            } catch (_: IllegalStateException) {
                // A decoder that failed mid-stream is no longer in a state to stop.
            }
            decoder?.release()
            extractor.release()
            if (!succeeded) output.delete()
        }
    }

    /**
     * What the decoder hands out, and how to read it as 16-bit samples for at
     * most two channels: LAME takes mono or stereo, so a surround track keeps
     * its front left and right.
     */
    private class PcmLayout(val sampleRate: Int, val channels: Int, val isFloat: Boolean) {
        val outputChannels: Int = minOf(channels, 2)
        private val bytesPerSample = if (isFloat) 4 else 2

        fun frames(byteCount: Int): Int = byteCount / (bytesPerSample * channels)

        fun read(buffer: java.nio.ByteBuffer, frames: Int, into: ShortArray) {
            if (!isFloat && channels == outputChannels) {
                buffer.asShortBuffer().get(into, 0, frames * channels)
                return
            }
            val start = buffer.position()
            for (frame in 0 until frames) {
                for (channel in 0 until outputChannels) {
                    val at = start + (frame * channels + channel) * bytesPerSample
                    into[frame * outputChannels + channel] = if (isFloat) {
                        (buffer.getFloat(at).coerceIn(-1f, 1f) * Short.MAX_VALUE).toInt().toShort()
                    } else {
                        buffer.getShort(at)
                    }
                }
            }
        }

        companion object {
            fun from(format: MediaFormat): PcmLayout = PcmLayout(
                sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
                // "pcm-encoding" is MediaFormat.KEY_PCM_ENCODING, named from API 24.
                isFloat = format.containsKey("pcm-encoding") &&
                    format.getInteger("pcm-encoding") == AudioFormat.ENCODING_PCM_FLOAT,
            )
        }
    }

    private fun MediaFormat.longOrNull(key: String): Long? = if (containsKey(key)) getLong(key) else null

    /**
     * The MP3 bitrate for a source of the given bitrate. MP3 needs more bits
     * than AAC or Opus for the same sound, so each band maps one step up.
     */
    private fun targetKbps(format: MediaFormat, fileBytes: Long, durationUs: Long): Int {
        val declared = if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
            format.getInteger(MediaFormat.KEY_BIT_RATE)
        } else {
            0
        }
        val sourceBps = when {
            declared > 0 -> declared.toLong()
            durationUs > 0 -> fileBytes * 8 * 1_000_000 / durationUs
            else -> 0L
        }
        return when {
            sourceBps <= 0 -> 192
            sourceBps <= 100_000 -> 128
            sourceBps <= 170_000 -> 192
            else -> 256
        }
    }

    companion object {
        private const val TIMEOUT_US = 10_000L
        private const val PROGRESS_STEP = 0.01

        /**
         * Ids asked to stop, held statically because the cancel arrives on the
         * platform thread while the conversion runs on its own worker.
         */
        private val cancelledJobs: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /** Marks [jobId] for cancellation; cleared when that job starts or ends. */
        fun cancel(jobId: String) {
            if (jobId.isNotEmpty()) cancelledJobs.add(jobId)
        }
    }
}
