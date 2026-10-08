/*
 * JNI layer between Mp3Encoder.kt and libmp3lame.
 *
 * One encoder is a `lame_global_flags` pointer handed to Kotlin as a long.
 * Kotlin owns its lifetime: open, encode any number of times, flush, close.
 */
#include <jni.h>
#include <stddef.h>

#include "lame.h"

JNIEXPORT jlong JNICALL
Java_com_vannt_nimbleclip_Mp3Encoder_nativeOpen(JNIEnv *env, jclass clazz, jint sample_rate,
                                                jint channels, jint kbps) {
    (void) env;
    (void) clazz;
    lame_global_flags *flags = lame_init();
    if (flags == NULL) return 0;

    lame_set_in_samplerate(flags, sample_rate);
    lame_set_num_channels(flags, channels);
    lame_set_mode(flags, channels == 1 ? MONO : JOINT_STEREO);
    lame_set_brate(flags, kbps);
    lame_set_quality(flags, 5);
    /* No Xing/LAME header: it is written by seeking back into a finished file,
       and a constant bitrate stream reads correctly without one. */
    lame_set_bWriteVbrTag(flags, 0);
    /* Nothing may go to stderr from inside an app. */
    lame_set_errorf(flags, NULL);
    lame_set_debugf(flags, NULL);
    lame_set_msgf(flags, NULL);

    if (lame_init_params(flags) < 0) {
        lame_close(flags);
        return 0;
    }
    return (jlong) (intptr_t) flags;
}

/*
 * Encodes `frames` sample frames of interleaved 16-bit PCM from `pcm` into
 * `out`. Returns the number of MP3 bytes written, or a negative LAME error.
 */
JNIEXPORT jint JNICALL
Java_com_vannt_nimbleclip_Mp3Encoder_nativeEncode(JNIEnv *env, jclass clazz, jlong handle,
                                                  jshortArray pcm, jint frames, jint channels,
                                                  jbyteArray out) {
    (void) clazz;
    lame_global_flags *flags = (lame_global_flags *) (intptr_t) handle;
    if (flags == NULL) return -1;

    jsize capacity = (*env)->GetArrayLength(env, out);
    jshort *samples = (*env)->GetShortArrayElements(env, pcm, NULL);
    jbyte *bytes = (*env)->GetByteArrayElements(env, out, NULL);
    if (samples == NULL || bytes == NULL) {
        if (samples != NULL) (*env)->ReleaseShortArrayElements(env, pcm, samples, JNI_ABORT);
        if (bytes != NULL) (*env)->ReleaseByteArrayElements(env, out, bytes, JNI_ABORT);
        return -1;
    }

    int written;
    if (channels == 1) {
        written = lame_encode_buffer(flags, samples, samples, frames, (unsigned char *) bytes,
                                     capacity);
    } else {
        written = lame_encode_buffer_interleaved(flags, samples, frames, (unsigned char *) bytes,
                                                 capacity);
    }

    (*env)->ReleaseShortArrayElements(env, pcm, samples, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, out, bytes, written > 0 ? 0 : JNI_ABORT);
    return written;
}

/* Writes the frames LAME was still holding. `out` needs room for 7200 bytes. */
JNIEXPORT jint JNICALL
Java_com_vannt_nimbleclip_Mp3Encoder_nativeFlush(JNIEnv *env, jclass clazz, jlong handle,
                                                 jbyteArray out) {
    (void) clazz;
    lame_global_flags *flags = (lame_global_flags *) (intptr_t) handle;
    if (flags == NULL) return -1;

    jsize capacity = (*env)->GetArrayLength(env, out);
    jbyte *bytes = (*env)->GetByteArrayElements(env, out, NULL);
    if (bytes == NULL) return -1;
    int written = lame_encode_flush(flags, (unsigned char *) bytes, capacity);
    (*env)->ReleaseByteArrayElements(env, out, bytes, written > 0 ? 0 : JNI_ABORT);
    return written;
}

JNIEXPORT void JNICALL
Java_com_vannt_nimbleclip_Mp3Encoder_nativeClose(JNIEnv *env, jclass clazz, jlong handle) {
    (void) env;
    (void) clazz;
    lame_global_flags *flags = (lame_global_flags *) (intptr_t) handle;
    if (flags != NULL) lame_close(flags);
}
