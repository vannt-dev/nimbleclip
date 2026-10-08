package com.vannt.nimbleclip

/**
 * libmp3lame behind four JNI calls; see `src/main/cpp/mp3_encoder_jni.c`.
 *
 * Android ships an MP3 decoder but no MP3 encoder, so the encoder is LAME,
 * built from source into `libnimbleclip_mp3.so`. A handle is a native pointer:
 * every [nativeOpen] that returns non-zero must be paired with [nativeClose].
 */
internal object Mp3Encoder {
    init {
        System.loadLibrary("nimbleclip_mp3")
    }

    /** Bytes [nativeFlush] may write; LAME's documented worst case. */
    const val FLUSH_BYTES = 7200

    /** LAME's documented worst case for encoding [frames] sample frames. */
    fun outputCapacity(frames: Int): Int = frames * 5 / 4 + FLUSH_BYTES

    /** Returns 0 when LAME rejects the parameters. */
    @JvmStatic
    external fun nativeOpen(sampleRate: Int, channels: Int, kbps: Int): Long

    /**
     * Encodes [frames] frames of interleaved 16-bit PCM. Returns the bytes
     * written to [out], or a negative LAME error.
     */
    @JvmStatic
    external fun nativeEncode(handle: Long, pcm: ShortArray, frames: Int, channels: Int, out: ByteArray): Int

    @JvmStatic
    external fun nativeFlush(handle: Long, out: ByteArray): Int

    @JvmStatic
    external fun nativeClose(handle: Long)
}
