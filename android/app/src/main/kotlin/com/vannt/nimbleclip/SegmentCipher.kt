package com.vannt.nimbleclip

import java.io.File
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Decrypts one segment of an HLS stream whose playlist names its key openly.
 *
 * `METHOD=AES-128` is AES in CBC mode over the whole segment with PKCS#7
 * padding, the key a 16-byte file any player fetches from the address in the
 * playlist. The platform's own cipher is used, which is hardware-backed where
 * the device has it: a long video is hundreds of megabytes of this.
 */
object SegmentCipher {
    fun decrypt(sourcePath: String, outputPath: String, key: ByteArray, iv: ByteArray): String {
        require(key.size == KEY_SIZE) { "an AES-128 key is $KEY_SIZE bytes, not ${key.size}" }
        require(iv.size == KEY_SIZE) { "an AES initialisation vector is $KEY_SIZE bytes, not ${iv.size}" }
        // Named PKCS5 by the platform; for a 16-byte block it is PKCS#7.
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        val output = File(outputPath)
        var succeeded = false
        try {
            CipherInputStream(File(sourcePath).inputStream().buffered(), cipher).use { input ->
                output.outputStream().buffered().use { input.copyTo(it, BUFFER_SIZE) }
            }
            succeeded = true
            return output.absolutePath
        } finally {
            if (!succeeded) output.delete()
        }
    }

    private const val KEY_SIZE = 16
    private const val BUFFER_SIZE = 1 shl 16
}
