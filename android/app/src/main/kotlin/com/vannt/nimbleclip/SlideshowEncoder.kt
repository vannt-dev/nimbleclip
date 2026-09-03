package com.vannt.nimbleclip

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.media.AudioFormat
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

/**
 * Raised for anything the caller can act on; the channel handler turns it
 * into an `encode_failed` (or `out_of_space`) platform error.
 */
class SlideshowEncodeException(message: String, cause: Throwable? = null) :
    Exception(message, cause)

/**
 * Renders a list of local image files into a single H.264/MP4 clip, with the
 * post's music transcoded to AAC alongside it when one is supplied.
 *
 * The audio stage runs to completion *before* the muxer is started, because
 * `MediaMuxer` will not accept a track added after `start()`. Every encoded
 * AAC packet is buffered along with the encoder's output `MediaFormat`; only
 * then are the video and audio tracks added and the muxer started. The order
 * also buys the failure property this feature needs: a music track that will
 * not decode cannot corrupt the picture, because it fails before a single
 * frame has been muxed. Any [Throwable] out of that stage — a missing file, an
 * unsupported codec, an `OutOfMemoryError` — leaves the render producing a
 * silent but valid MP4 with [Result.audioSkipped] set. A slideshow without
 * music is usable; a failed render is not.
 *
 * Frames are fed as raw YUV through `queueInputBuffer` rather than through a
 * `createInputSurface()` Canvas. An encoder input surface is a hardware
 * producer buffer: `Surface.lockCanvas` on it is not supported, and the
 * alternative — an EGL context plus shaders purely to blit one bitmap — buys
 * nothing here. Feeding buffers also lets the presentation timestamps come
 * straight from a frame counter instead of a wall clock.
 */
class SlideshowEncoder {
    data class Request(
        val imagePaths: List<String>,
        val audioPath: String?,
        val perImageMs: Int,
        val width: Int,
        val height: Int,
        val outputPath: String,
    )

    data class Result(val filePath: String, val audioSkipped: Boolean)

    fun encode(request: Request): Result {
        if (request.imagePaths.isEmpty()) {
            throw SlideshowEncodeException("no images to render")
        }
        // H.264 needs even dimensions, and every chroma sample covers a 2x2
        // luma block, so an odd edge would read past the plane.
        val width = evenLength(request.width)
        val height = evenLength(request.height)
        val framesPerImage = max(1, request.perImageMs * FRAME_RATE / 1000)
        // The picture's length is known up front, so the audio can be trimmed
        // to it while it is being transcoded rather than after. That is what
        // bounds the buffered packets: a four-minute song behind a six-second
        // slideshow costs six seconds of AAC, not four minutes of it.
        val videoDurationUs =
            request.imagePaths.size.toLong() * framesPerImage * 1_000_000L / FRAME_RATE

        val output = File(request.outputPath)
        output.parentFile?.mkdirs()
        if (output.exists()) output.delete()

        // Before the muxer exists, so nothing it has written can be at risk.
        val audio = transcodeAudioOrNull(request.audioPath, videoDurationUs)

        var codec: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var succeeded = false
        try {
            codec = MediaCodec.createEncoderByType(MIME_TYPE)
            codec.configure(
                videoFormat(width, height),
                null,
                null,
                MediaCodec.CONFIGURE_FLAG_ENCODE,
            )
            codec.start()
            muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val sink = MuxerSink(codec, muxer, audio)
            var frameIndex = 0L
            for (path in request.imagePaths) {
                val frame = composeFrame(path, width, height)
                repeat(framesPerImage) {
                    submitFrame(codec, frame, frameIndex, sink)
                    frameIndex++
                }
            }
            if (frameIndex == 0L) {
                throw SlideshowEncodeException("no frames were produced")
            }
            signalEndOfStream(codec, frameIndex, sink)
            sink.drain(endOfStream = true)
            succeeded = true
        } catch (error: SlideshowEncodeException) {
            throw error
        } catch (error: Exception) {
            throw SlideshowEncodeException(error.message ?: error.toString(), error)
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            // Stopping the muxer is what writes the moov box; a muxer that was
            // never started throws instead, hence the runCatching.
            runCatching { muxer?.stop() }
            runCatching { muxer?.release() }
            if (!succeeded) runCatching { output.delete() }
        }

        if (!output.exists() || output.length() == 0L) {
            throw SlideshowEncodeException("the encoder produced no output file")
        }
        return Result(filePath = output.absolutePath, audioSkipped = audio == null)
    }

    /**
     * Reads back a finished file so callers can prove it is decodable rather
     * than merely present. Task 9 reuses this to assert the audio track.
     */
    fun probe(path: String): Map<String, Any?> {
        val retriever = openLocal(path)
        try {
            fun read(key: Int) = retriever.extractMetadata(key)
            return mapOf(
                "durationMs" to (read(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toIntOrNull() ?: 0),
                "width" to (read(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0),
                "height" to (read(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0),
                "hasVideo" to (read(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"),
                "hasAudio" to (read(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"),
            )
        } catch (error: Exception) {
            throw SlideshowEncodeException(
                "could not read back $path: ${error.message}",
                error,
            )
        } finally {
            runCatching { retriever.release() }
        }
    }

    /**
     * Decodes one frame of a finished file and reports the colour at three
     * points on it.
     *
     * This exists so a test can prove the *picture*, not just the container.
     * The ARGB-to-I420 conversion and the plane writes in [YuvFrame] are hand
     * rolled: a red/blue swap, a U/V mix-up, a row-stride error or an
     * all-black frame each still produce a perfectly well-formed MP4 of the
     * right size, duration and track layout. Sampling the centre and two
     * corners catches the colour faults, and requiring all three to agree on a
     * uniform source catches the stride faults, which skew the image.
     */
    fun frameColorAt(path: String, atMs: Int): Map<String, Any?> {
        val retriever = openLocal(path)
        try {
            val frame = retriever.getFrameAtTime(
                atMs.toLong() * 1000L,
                MediaMetadataRetriever.OPTION_CLOSEST,
            ) ?: throw SlideshowEncodeException("no frame decoded at ${atMs}ms in $path")
            try {
                return mapOf(
                    "width" to frame.width,
                    "height" to frame.height,
                    // Signed ints on the Dart side; masked to keep the channel
                    // payload a plain unsigned ARGB value.
                    "center" to (frame.getPixel(frame.width / 2, frame.height / 2) and 0xFFFFFF),
                    "topLeft" to (frame.getPixel(4, 4) and 0xFFFFFF),
                    "bottomRight" to
                        (frame.getPixel(frame.width - 5, frame.height - 5) and 0xFFFFFF),
                )
            } finally {
                frame.recycle()
            }
        } catch (error: SlideshowEncodeException) {
            throw error
        } catch (error: Exception) {
            throw SlideshowEncodeException(
                "could not decode a frame of $path: ${error.message}",
                error,
            )
        } finally {
            runCatching { retriever.release() }
        }
    }

    /**
     * Opens a retriever on a local file only.
     *
     * `setDataSource(String)` happily resolves an http(s) URL. This feature's
     * Kotlin is specified never to touch the network — it receives local paths
     * — so the guard makes that structural here the same way `decodeScaled`
     * already does it for images, rather than depending on every caller.
     */
    private fun openLocal(path: String): MediaMetadataRetriever {
        val file = File(path)
        if (!file.isFile) {
            throw SlideshowEncodeException("not a local file: $path")
        }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
        } catch (error: Exception) {
            runCatching { retriever.release() }
            throw SlideshowEncodeException(
                "could not read back $path: ${error.message}",
                error,
            )
        }
        return retriever
    }

    private fun videoFormat(width: Int, height: Int): MediaFormat =
        MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, width * height * 4)
            setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

    private fun submitFrame(
        codec: MediaCodec,
        frame: YuvFrame,
        frameIndex: Long,
        sink: MuxerSink,
    ) {
        var attempts = 0
        while (true) {
            val index = codec.dequeueInputBuffer(TIMEOUT_US)
            if (index >= 0) {
                val image = codec.getInputImage(index)
                    ?: throw SlideshowEncodeException(
                        "the encoder did not expose a YUV input image",
                    )
                frame.writeInto(image)
                // Derived from the planes, not from width*height*3/2: an
                // encoder that pads rows or aligns height writes more bytes
                // than the nominal frame size, and a codec that honours the
                // declared size would then see a truncated frame.
                val declared = frame.bufferExtent(image)
                val capacity = codec.getInputBuffer(index)?.capacity() ?: declared
                codec.queueInputBuffer(
                    index,
                    0,
                    min(declared, capacity),
                    frameIndex * 1_000_000L / FRAME_RATE,
                    0,
                )
                return
            }
            // No input buffer free yet: the encoder is holding them until its
            // output is collected, so drain before trying again.
            sink.drain(endOfStream = false)
            if (++attempts > MAX_STALLED_ATTEMPTS) {
                throw SlideshowEncodeException("the encoder stopped accepting frames")
            }
        }
    }

    private fun signalEndOfStream(codec: MediaCodec, frameIndex: Long, sink: MuxerSink) {
        var attempts = 0
        while (true) {
            val index = codec.dequeueInputBuffer(TIMEOUT_US)
            if (index >= 0) {
                codec.queueInputBuffer(
                    index,
                    0,
                    0,
                    frameIndex * 1_000_000L / FRAME_RATE,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
                return
            }
            sink.drain(endOfStream = false)
            if (++attempts > MAX_STALLED_ATTEMPTS) {
                throw SlideshowEncodeException("the encoder never accepted end of stream")
            }
        }
    }

    /**
     * Paints one image onto a [width]x[height] frame: a blurred copy scaled to
     * cover the whole canvas, then the image itself scaled to fit inside it.
     */
    private fun composeFrame(path: String, width: Int, height: Int): YuvFrame {
        val source = decodeScaled(path, width, height)
        try {
            val canvasBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            try {
                val canvas = Canvas(canvasBitmap)
                canvas.drawColor(Color.BLACK)
                drawBlurredCover(canvas, source, width, height)
                drawFitted(canvas, source, width, height)
                return YuvFrame(canvasBitmap)
            } finally {
                canvasBitmap.recycle()
            }
        } finally {
            source.recycle()
        }
    }

    private fun decodeScaled(path: String, width: Int, height: Int): Bitmap {
        val file = File(path)
        if (!file.isFile) {
            throw SlideshowEncodeException("image not found: $path")
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw SlideshowEncodeException("could not decode image: $path")
        }
        val sample = sampleSizeFor(bounds.outWidth, bounds.outHeight, width, height)
        val bitmap = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        ) ?: throw SlideshowEncodeException("could not decode image: $path")
        return bitmap
    }

    /**
     * The smallest power-of-two `inSampleSize` that brings a source down to a
     * total-pixel budget.
     *
     * Budgeting *area* rather than comparing each axis is the whole point: a
     * per-axis test joined with `&&` never fires for a landscape source against
     * a portrait frame, because the source's short axis is already under the
     * frame's long one. A 4032x3024 phone photo would sail through such a test
     * at full size and cost ~48 MB of ARGB_8888.
     *
     * The budget is twice the canvas's pixel count. Since each step quarters
     * the area, the decoded source keeps at least half the canvas's pixels,
     * which is comfortably more than a letterboxed fit ever draws.
     */
    private fun sampleSizeFor(
        sourceWidth: Int,
        sourceHeight: Int,
        width: Int,
        height: Int,
    ): Int {
        val budget = 2L * width * height
        var sample = 1
        while (sample < MAX_SAMPLE_SIZE &&
            (sourceWidth.toLong() / sample) * (sourceHeight.toLong() / sample) > budget
        ) {
            sample *= 2
        }
        return sample
    }

    /**
     * One blur path for every API level. `RenderEffect` needs a RenderNode or
     * a View and only exists on API 31+, which would leave the API 24-30 path
     * shipping untested; a downscale-then-upscale is uniform, free, and reads
     * as a blur at this size.
     */
    private fun drawBlurredCover(canvas: Canvas, source: Bitmap, width: Int, height: Int) {
        val smallWidth = max(1, width / BLUR_DIVISOR)
        val smallHeight = max(1, height / BLUR_DIVISOR)
        val small = Bitmap.createBitmap(smallWidth, smallHeight, Bitmap.Config.ARGB_8888)
        try {
            val smallCanvas = Canvas(small)
            smallCanvas.drawColor(Color.BLACK)
            smallCanvas.drawBitmap(
                source,
                coverSourceRect(source, smallWidth, smallHeight),
                RectF(0f, 0f, smallWidth.toFloat(), smallHeight.toFloat()),
                filterPaint,
            )
            canvas.drawBitmap(
                small,
                null,
                RectF(0f, 0f, width.toFloat(), height.toFloat()),
                filterPaint,
            )
        } finally {
            small.recycle()
        }
    }

    private fun drawFitted(canvas: Canvas, source: Bitmap, width: Int, height: Int) {
        val scale = min(
            width.toFloat() / source.width,
            height.toFloat() / source.height,
        )
        val drawWidth = source.width * scale
        val drawHeight = source.height * scale
        val left = (width - drawWidth) / 2f
        val top = (height - drawHeight) / 2f
        canvas.drawBitmap(
            source,
            null,
            RectF(left, top, left + drawWidth, top + drawHeight),
            filterPaint,
        )
    }

    /**
     * The centred crop of [source] whose aspect ratio matches the destination,
     * i.e. the region a "cover" scale would leave visible.
     */
    private fun coverSourceRect(source: Bitmap, width: Int, height: Int): Rect {
        val scale = max(
            width.toFloat() / source.width,
            height.toFloat() / source.height,
        )
        val visibleWidth = min(source.width.toFloat(), width / scale)
        val visibleHeight = min(source.height.toFloat(), height / scale)
        val left = (source.width - visibleWidth) / 2f
        val top = (source.height - visibleHeight) / 2f
        return Rect(
            left.toInt(),
            top.toInt(),
            (left + visibleWidth).toInt(),
            (top + visibleHeight).toInt(),
        )
    }

    private val filterPaint = Paint().apply {
        isFilterBitmap = true
        isAntiAlias = true
        isDither = true
    }

    private fun evenLength(value: Int): Int {
        if (value < 2) throw SlideshowEncodeException("invalid frame size: $value")
        return value - (value % 2)
    }

    /** One encoded AAC access unit, held until the muxer is ready for it. */
    private class AudioPacket(
        val data: ByteArray,
        val presentationTimeUs: Long,
        val flags: Int,
    )

    /** The whole music track, encoded and waiting for a muxer to accept it. */
    private class EncodedAudio(val format: MediaFormat, val packets: List<AudioPacket>)

    /**
     * Transcodes the post's music, or returns null if it cannot be used.
     *
     * Null is a normal outcome, not an error: no path given, a path that is not
     * a file, a container with no audio track, a codec the device does not
     * have, a decoder that chokes on the bytes. Every one of them ends the same
     * way — a silent slideshow that still renders. [Throwable] rather than
     * [Exception] is caught for the same reason the channel handler does it: a
     * decoder handed a malformed header can raise an `Error`, and letting one
     * escape here would fail a render that has a perfectly good picture
     * available.
     */
    private fun transcodeAudioOrNull(audioPath: String?, limitUs: Long): EncodedAudio? {
        if (audioPath.isNullOrBlank()) return null
        return try {
            transcodeAudio(audioPath, limitUs)
        } catch (error: Throwable) {
            null
        }
    }

    /**
     * Decodes [audioPath] to PCM and re-encodes it as AAC-LC, trimmed to
     * [limitUs].
     *
     * TikWM serves MP3 and `MediaMuxer` will not put MP3 in an MP4, so a
     * transcode is unavoidable. Both codecs are driven from one loop rather
     * than decoding fully and then encoding: a decode-then-encode would hold
     * the entire PCM stream — about 10 MB per minute at 44.1 kHz stereo —
     * where this holds only what the encoder has not yet consumed.
     *
     * The output format is taken from the *decoder*, not fixed at 44.1 kHz
     * stereo. `MediaCodec` neither resamples nor remixes, so declaring a rate
     * the decoder is not producing does not convert the audio — it just
     * mislabels it, and the music plays back at the wrong speed. Whatever the
     * source turns out to be is what gets encoded, at [AUDIO_BIT_RATE].
     */
    private fun transcodeAudio(audioPath: String, limitUs: Long): EncodedAudio {
        val file = File(audioPath)
        // Same guard as openLocal: setDataSource(String) resolves http(s) URLs
        // and this feature's Kotlin never touches the network.
        if (!file.isFile) {
            throw SlideshowEncodeException("audio file not found: $audioPath")
        }
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.absolutePath)
            val track = firstAudioTrack(extractor)
            val sourceFormat = extractor.getTrackFormat(track)
            val sourceMime = sourceFormat.getString(MediaFormat.KEY_MIME)
                ?: throw SlideshowEncodeException("audio track has no mime type")
            extractor.selectTrack(track)
            val activeDecoder = MediaCodec.createDecoderByType(sourceMime)
            decoder = activeDecoder
            activeDecoder.configure(sourceFormat, null, null, 0)
            activeDecoder.start()

            val packets = ArrayList<AudioPacket>()
            val decoderInfo = MediaCodec.BufferInfo()
            val encoderInfo = MediaCodec.BufferInfo()
            // Decoded PCM the encoder has not swallowed yet. Partially consumed
            // from the head, because an encoder input buffer is rarely the same
            // size as a decoder output buffer.
            val pending = ArrayDeque<ByteBuffer>()
            var encoderFormat: MediaFormat? = null
            var bytesPerSecond = 0L
            var bytesFed = 0L
            var extractorDone = false
            var decoderDone = false
            var encoderInputDone = false
            var encoderDone = false
            var idleRounds = 0

            while (!encoderDone) {
                var progressed = false

                if (!extractorDone) {
                    val index = activeDecoder.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        progressed = true
                        val buffer = activeDecoder.getInputBuffer(index)
                            ?: throw SlideshowEncodeException("no audio decoder input buffer")
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            activeDecoder.queueInputBuffer(
                                index,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            extractorDone = true
                        } else {
                            activeDecoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                if (!decoderDone && pending.size < MAX_PENDING_PCM_CHUNKS) {
                    when (val index = activeDecoder.dequeueOutputBuffer(decoderInfo, TIMEOUT_US)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            progressed = true
                            if (encoder == null) {
                                val pcm = activeDecoder.outputFormat
                                encoder = createAudioEncoder(pcm)
                                bytesPerSecond = pcmBytesPerSecond(pcm)
                            }
                        }
                        else -> if (index >= 0) {
                            progressed = true
                            val buffer = activeDecoder.getOutputBuffer(index)
                            if (buffer != null && decoderInfo.size > 0) {
                                val copy = ByteArray(decoderInfo.size)
                                buffer.position(decoderInfo.offset)
                                buffer.limit(decoderInfo.offset + decoderInfo.size)
                                buffer.get(copy)
                                pending.addLast(ByteBuffer.wrap(copy))
                            }
                            val eos =
                                decoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            activeDecoder.releaseOutputBuffer(index, false)
                            if (eos) decoderDone = true
                        }
                    }
                }

                if (decoderDone && encoder == null) {
                    throw SlideshowEncodeException("the audio decoder produced no output format")
                }

                val activeEncoder = encoder
                if (activeEncoder != null &&
                    !encoderInputDone &&
                    (pending.isNotEmpty() || decoderDone)
                ) {
                    val index = activeEncoder.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        progressed = true
                        val input = activeEncoder.getInputBuffer(index)
                            ?: throw SlideshowEncodeException("no audio encoder input buffer")
                        input.clear()
                        var written = 0
                        while (pending.isNotEmpty() && input.hasRemaining()) {
                            val head = pending.first()
                            val take = min(head.remaining(), input.remaining())
                            val slice = head.slice()
                            slice.limit(take)
                            input.put(slice)
                            head.position(head.position() + take)
                            written += take
                            if (!head.hasRemaining()) pending.removeFirst()
                        }
                        // Timestamps come from the byte count rather than from
                        // the decoder's own, which the encoder requires to be
                        // monotonic and which a seek-free straight read makes
                        // exact anyway.
                        val presentationTimeUs = bytesToUs(bytesFed, bytesPerSecond)
                        if (written == 0 && decoderDone) {
                            activeEncoder.queueInputBuffer(
                                index,
                                0,
                                0,
                                presentationTimeUs,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            encoderInputDone = true
                        } else {
                            activeEncoder.queueInputBuffer(
                                index,
                                0,
                                written,
                                presentationTimeUs,
                                0,
                            )
                            bytesFed += written
                            if (bytesToUs(bytesFed, bytesPerSecond) >= limitUs) {
                                // The music outlasts the pictures; stop reading
                                // it and let the next round close the encoder.
                                extractorDone = true
                                decoderDone = true
                                pending.clear()
                            }
                        }
                    }
                }

                if (activeEncoder != null) {
                    when (val index = activeEncoder.dequeueOutputBuffer(encoderInfo, TIMEOUT_US)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            progressed = true
                            encoderFormat = activeEncoder.outputFormat
                        }
                        else -> if (index >= 0) {
                            progressed = true
                            val buffer = activeEncoder.getOutputBuffer(index)
                            // As with the video track: the codec-config buffer
                            // is the ASC, which the muxer already has from the
                            // output format.
                            val isConfig =
                                encoderInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (buffer != null && !isConfig && encoderInfo.size > 0) {
                                val data = ByteArray(encoderInfo.size)
                                buffer.position(encoderInfo.offset)
                                buffer.limit(encoderInfo.offset + encoderInfo.size)
                                buffer.get(data)
                                packets.add(
                                    AudioPacket(
                                        data = data,
                                        presentationTimeUs = encoderInfo.presentationTimeUs,
                                        // Every AAC access unit is a sync
                                        // sample; the END_OF_STREAM bit must
                                        // not reach the muxer.
                                        flags = MediaCodec.BUFFER_FLAG_KEY_FRAME,
                                    ),
                                )
                            }
                            val eos =
                                encoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            activeEncoder.releaseOutputBuffer(index, false)
                            if (eos) encoderDone = true
                        }
                    }
                }

                if (progressed) {
                    idleRounds = 0
                } else if (++idleRounds > MAX_STALLED_ATTEMPTS) {
                    throw SlideshowEncodeException("the audio transcode stalled")
                }
            }

            val format = encoderFormat
                ?: throw SlideshowEncodeException("the audio encoder produced no output format")
            if (packets.isEmpty()) {
                throw SlideshowEncodeException("the audio encoder produced no packets")
            }
            return EncodedAudio(format, packets)
        } finally {
            runCatching { decoder?.stop() }
            runCatching { decoder?.release() }
            runCatching { encoder?.stop() }
            runCatching { encoder?.release() }
            runCatching { extractor.release() }
        }
    }

    private fun firstAudioTrack(extractor: MediaExtractor): Int {
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME).orEmpty()
            if (mime.startsWith("audio/")) return index
        }
        throw SlideshowEncodeException("no audio track to transcode")
    }

    /**
     * Configures an AAC-LC encoder to match the PCM the decoder is producing.
     *
     * The decoder's rate and channel count are carried straight through. A
     * PCM encoding other than 16-bit is rejected rather than fed through: the
     * encoder would read float samples as shorts and emit noise, which is a
     * far worse outcome than the silent fallback.
     */
    private fun createAudioEncoder(pcmFormat: MediaFormat): MediaCodec {
        if (pcmFormat.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
            pcmFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) != AudioFormat.ENCODING_PCM_16BIT
        ) {
            throw SlideshowEncodeException("the audio decoder produced non 16-bit PCM")
        }
        val sampleRate = pcmFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = pcmFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val format = MediaFormat.createAudioFormat(AUDIO_MIME, sampleRate, channelCount).apply {
            setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BIT_RATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, AUDIO_MAX_INPUT_SIZE)
        }
        val encoder = MediaCodec.createEncoderByType(AUDIO_MIME)
        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
        } catch (error: Throwable) {
            runCatching { encoder.release() }
            throw error
        }
        return encoder
    }

    private fun pcmBytesPerSecond(pcmFormat: MediaFormat): Long {
        val sampleRate = pcmFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE).toLong()
        val channelCount = pcmFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT).toLong()
        val bytes = sampleRate * channelCount * 2L
        if (bytes <= 0L) {
            throw SlideshowEncodeException("the audio decoder reported an empty PCM format")
        }
        return bytes
    }

    private fun bytesToUs(bytes: Long, bytesPerSecond: Long): Long =
        if (bytesPerSecond <= 0L) 0L else bytes * 1_000_000L / bytesPerSecond

    /**
     * Collects video-encoder output and writes it to the muxer, interleaving
     * the already-encoded audio packets as it goes.
     *
     * The video track can only be added once the encoder has emitted its
     * output format, which happens after the first frames are queued — hence
     * the deferred `addTrack` rather than doing it up front. `start()` waits
     * for that same moment because `MediaMuxer` refuses a track added after
     * it: both tracks go in together, which is only possible because [audio]
     * was fully transcoded before this sink was built.
     */
    private class MuxerSink(
        private val codec: MediaCodec,
        private val muxer: MediaMuxer,
        private val audio: EncodedAudio?,
    ) {
        private val info = MediaCodec.BufferInfo()
        private val audioInfo = MediaCodec.BufferInfo()
        private var trackIndex = -1
        private var audioTrackIndex = -1
        private var nextAudioPacket = 0
        private var started = false

        fun drain(endOfStream: Boolean) {
            var idleRounds = 0
            while (true) {
                when (val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (!endOfStream) return
                        if (++idleRounds > MAX_STALLED_ATTEMPTS) {
                            throw SlideshowEncodeException(
                                "the encoder never signalled end of stream",
                            )
                        }
                    }
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (started) {
                            throw SlideshowEncodeException("the encoder changed format twice")
                        }
                        // Every track this file will ever have, added before
                        // start() and never after it.
                        trackIndex = muxer.addTrack(codec.outputFormat)
                        if (audio != null) {
                            audioTrackIndex = muxer.addTrack(audio.format)
                        }
                        muxer.start()
                        started = true
                    }
                    else -> {
                        if (index < 0) continue
                        idleRounds = 0
                        writeSample(index)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            // The picture is done; anything of the music left
                            // over belongs at the tail.
                            writeAudioUpTo(Long.MAX_VALUE)
                            return
                        }
                    }
                }
            }
        }

        private fun writeSample(index: Int) {
            val buffer: ByteBuffer? = codec.getOutputBuffer(index)
            // The codec-config buffer holds SPS/PPS, which MediaMuxer already
            // took from the output format; writing it again corrupts the track.
            val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
            if (buffer != null && !isConfig && info.size > 0 && started) {
                // Keeping the two tracks roughly in step as they are written
                // is what lets a player stream the result instead of seeking
                // back and forth between one long run of audio and one of
                // video.
                writeAudioUpTo(info.presentationTimeUs)
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                muxer.writeSampleData(trackIndex, buffer, info)
            }
            codec.releaseOutputBuffer(index, false)
        }

        private fun writeAudioUpTo(presentationTimeUs: Long) {
            if (audio == null || !started) return
            while (nextAudioPacket < audio.packets.size) {
                val packet = audio.packets[nextAudioPacket]
                if (packet.presentationTimeUs > presentationTimeUs) return
                val buffer = ByteBuffer.wrap(packet.data)
                audioInfo.set(0, packet.data.size, packet.presentationTimeUs, packet.flags)
                muxer.writeSampleData(audioTrackIndex, buffer, audioInfo)
                nextAudioPacket++
            }
        }
    }

    /**
     * A composed frame held as I420 planes, converted from ARGB once and then
     * copied into as many encoder buffers as the image's duration needs.
     */
    private class YuvFrame(bitmap: Bitmap) {
        val width = bitmap.width
        val height = bitmap.height
        private val luma = ByteArray(width * height)
        private val chromaU = ByteArray(width / 2 * (height / 2))
        private val chromaV = ByteArray(width / 2 * (height / 2))

        init {
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            convert(pixels)
        }

        private fun convert(pixels: IntArray) {
            val halfWidth = width / 2
            for (y in 0 until height) {
                val rowStart = y * width
                for (x in 0 until width) {
                    val pixel = pixels[rowStart + x]
                    val r = (pixel shr 16) and 0xFF
                    val g = (pixel shr 8) and 0xFF
                    val b = pixel and 0xFF
                    // BT.601 studio swing, which is what an AVC encoder expects
                    // from a YUV420 input buffer.
                    luma[rowStart + x] =
                        (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()
                    if ((y and 1) == 0 && (x and 1) == 0) {
                        val chromaIndex = (y / 2) * halfWidth + (x / 2)
                        chromaU[chromaIndex] =
                            (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte()
                        chromaV[chromaIndex] =
                            (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte()
                    }
                }
            }
        }

        fun writeInto(image: Image) {
            if (image.width < width || image.height < height) {
                throw SlideshowEncodeException(
                    "encoder buffer is ${image.width}x${image.height}, " +
                        "smaller than the ${width}x$height frame",
                )
            }
            writeLuma(image.planes[0])
            writeChroma(image.planes[1], chromaU)
            writeChroma(image.planes[2], chromaV)
        }

        /**
         * How many bytes of the input buffer this frame actually spans.
         *
         * Rows may be padded, so the extent is driven by `rowStride`. In a
         * semi-planar buffer the two chroma planes are the same memory
         * interleaved, so their extent is counted once rather than twice.
         */
        fun bufferExtent(image: Image): Int {
            val luma = image.planes[0]
            val chroma = image.planes[1]
            val lumaBytes = luma.rowStride * height
            val chromaRows = height / 2
            val chromaBytes = if (chroma.pixelStride > 1) {
                chroma.rowStride * chromaRows
            } else {
                chroma.rowStride * chromaRows + image.planes[2].rowStride * chromaRows
            }
            return lumaBytes + chromaBytes
        }

        private fun writeLuma(plane: Image.Plane) {
            val buffer = plane.buffer
            val rowStride = plane.rowStride
            if (plane.pixelStride == 1) {
                for (y in 0 until height) {
                    buffer.position(y * rowStride)
                    buffer.put(luma, y * width, width)
                }
            } else {
                val pixelStride = plane.pixelStride
                for (y in 0 until height) {
                    val base = y * rowStride
                    for (x in 0 until width) {
                        buffer.put(base + x * pixelStride, luma[y * width + x])
                    }
                }
            }
        }

        /**
         * Written sample by sample rather than row by row on purpose: a
         * semi-planar encoder buffer interleaves U and V in the same memory, so
         * a bulk row copy into one plane would trample the other's samples.
         */
        private fun writeChroma(plane: Image.Plane, samples: ByteArray) {
            val buffer = plane.buffer
            val rowStride = plane.rowStride
            val pixelStride = plane.pixelStride
            val halfWidth = width / 2
            val halfHeight = height / 2
            if (pixelStride == 1) {
                for (y in 0 until halfHeight) {
                    buffer.position(y * rowStride)
                    buffer.put(samples, y * halfWidth, halfWidth)
                }
                return
            }
            for (y in 0 until halfHeight) {
                val base = y * rowStride
                val sampleRow = y * halfWidth
                for (x in 0 until halfWidth) {
                    buffer.put(base + x * pixelStride, samples[sampleRow + x])
                }
            }
        }
    }

    private companion object {
        const val MIME_TYPE = "video/avc"
        const val FRAME_RATE = 30
        const val BLUR_DIVISOR = 16
        const val TIMEOUT_US = 10_000L
        const val MAX_STALLED_ATTEMPTS = 500
        const val MAX_SAMPLE_SIZE = 1 shl 12
        const val AUDIO_MIME = "audio/mp4a-latm"
        const val AUDIO_BIT_RATE = 128_000
        const val AUDIO_MAX_INPUT_SIZE = 1 shl 16

        /**
         * How much decoded PCM may sit ahead of the AAC encoder before the
         * decoder is left to wait. Small on purpose: the queue exists to
         * absorb the mismatch between one decoder buffer and one encoder
         * buffer, not to hold the song.
         */
        const val MAX_PENDING_PCM_CHUNKS = 8
    }
}
