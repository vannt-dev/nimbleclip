package com.vannt.nimbleclip

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
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
 * Renders a list of local image files into a single H.264/MP4 clip.
 *
 * Picture only: audio is Task 9's job, so [Result.audioSkipped] is always
 * true and [Request.audioPath] is accepted but ignored.
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

        val output = File(request.outputPath)
        output.parentFile?.mkdirs()
        if (output.exists()) output.delete()

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

            val sink = MuxerSink(codec, muxer)
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
        return Result(filePath = output.absolutePath, audioSkipped = true)
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

    /**
     * Collects encoder output and writes it to the muxer.
     *
     * The muxer's track can only be added once the encoder has emitted its
     * output format, which happens after the first frames are queued — hence
     * the deferred `addTrack`/`start` rather than doing it up front.
     */
    private class MuxerSink(
        private val codec: MediaCodec,
        private val muxer: MediaMuxer,
    ) {
        private val info = MediaCodec.BufferInfo()
        private var trackIndex = -1
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
                        trackIndex = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        started = true
                    }
                    else -> {
                        if (index < 0) continue
                        idleRounds = 0
                        writeSample(index)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
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
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                muxer.writeSampleData(trackIndex, buffer, info)
            }
            codec.releaseOutputBuffer(index, false)
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
    }
}
