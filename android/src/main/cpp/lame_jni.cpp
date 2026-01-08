#include <jni.h>
#include <android/log.h>
#include <lame/lame.h>
#include <cstring>

#define LOG_TAG "LameEncoderJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

/**
 * Create and initialize a LAME encoder instance.
 * Returns encoder handle as jlong, or 0 on failure.
 */
JNIEXPORT jlong JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeCreate(
    JNIEnv *env,
    jobject thiz,
    jint inSampleRate,
    jint outSampleRate,
    jint channels,
    jint bitrate,
    jint quality
) {
    lame_t lame = lame_init();
    if (lame == nullptr) {
        LOGE("Failed to initialize LAME encoder");
        return 0;
    }

    // Configure encoder
    lame_set_in_samplerate(lame, inSampleRate);
    lame_set_out_samplerate(lame, outSampleRate);
    lame_set_num_channels(lame, channels);
    lame_set_brate(lame, bitrate);
    lame_set_quality(lame, quality);  // 0=best, 9=worst

    // Initialize parameters
    int result = lame_init_params(lame);
    if (result < 0) {
        LOGE("Failed to initialize LAME params: %d", result);
        lame_close(lame);
        return 0;
    }

    LOGI("Created LAME encoder: in=%dHz, out=%dHz, ch=%d, bitrate=%d, quality=%d",
         inSampleRate, outSampleRate, channels, bitrate, quality);

    return reinterpret_cast<jlong>(lame);
}

/**
 * Destroy a LAME encoder instance.
 */
JNIEXPORT void JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeDestroy(
    JNIEnv *env,
    jobject thiz,
    jlong lameHandle
) {
    if (lameHandle != 0) {
        lame_t lame = reinterpret_cast<lame_t>(lameHandle);
        lame_close(lame);
        LOGI("Destroyed LAME encoder");
    }
}

/**
 * Encode interleaved PCM samples to MP3.
 * Returns number of bytes written to output buffer, or negative on error.
 */
JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeEncodeInterleaved(
    JNIEnv *env,
    jobject thiz,
    jlong lameHandle,
    jshortArray pcmData,
    jint numSamples,
    jbyteArray mp3Buffer
) {
    if (lameHandle == 0) {
        LOGE("Invalid LAME handle");
        return -1;
    }

    lame_t lame = reinterpret_cast<lame_t>(lameHandle);

    // Get PCM samples
    jshort *pcm = env->GetShortArrayElements(pcmData, nullptr);
    if (pcm == nullptr) {
        LOGE("Failed to get PCM array");
        return -1;
    }

    // Get output buffer
    jbyte *mp3 = env->GetByteArrayElements(mp3Buffer, nullptr);
    if (mp3 == nullptr) {
        env->ReleaseShortArrayElements(pcmData, pcm, JNI_ABORT);
        LOGE("Failed to get MP3 buffer");
        return -1;
    }

    jint mp3BufferSize = env->GetArrayLength(mp3Buffer);

    // Encode
    int encodedBytes = lame_encode_buffer_interleaved(
        lame,
        pcm,
        numSamples,
        reinterpret_cast<unsigned char *>(mp3),
        mp3BufferSize
    );

    // Release arrays
    env->ReleaseShortArrayElements(pcmData, pcm, JNI_ABORT);
    env->ReleaseByteArrayElements(mp3Buffer, mp3, 0);

    if (encodedBytes < 0) {
        LOGE("LAME encode failed: %d", encodedBytes);
    }

    return encodedBytes;
}

/**
 * Encode mono PCM samples to MP3.
 * Returns number of bytes written to output buffer, or negative on error.
 */
JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeEncodeMono(
    JNIEnv *env,
    jobject thiz,
    jlong lameHandle,
    jshortArray pcmData,
    jint numSamples,
    jbyteArray mp3Buffer
) {
    if (lameHandle == 0) {
        LOGE("Invalid LAME handle");
        return -1;
    }

    lame_t lame = reinterpret_cast<lame_t>(lameHandle);

    // Get PCM samples
    jshort *pcm = env->GetShortArrayElements(pcmData, nullptr);
    if (pcm == nullptr) {
        LOGE("Failed to get PCM array");
        return -1;
    }

    // Get output buffer
    jbyte *mp3 = env->GetByteArrayElements(mp3Buffer, nullptr);
    if (mp3 == nullptr) {
        env->ReleaseShortArrayElements(pcmData, pcm, JNI_ABORT);
        LOGE("Failed to get MP3 buffer");
        return -1;
    }

    jint mp3BufferSize = env->GetArrayLength(mp3Buffer);

    // Encode mono (same buffer for left and right)
    int encodedBytes = lame_encode_buffer(
        lame,
        pcm,  // left channel
        pcm,  // right channel (same for mono)
        numSamples,
        reinterpret_cast<unsigned char *>(mp3),
        mp3BufferSize
    );

    // Release arrays
    env->ReleaseShortArrayElements(pcmData, pcm, JNI_ABORT);
    env->ReleaseByteArrayElements(mp3Buffer, mp3, 0);

    if (encodedBytes < 0) {
        LOGE("LAME encode mono failed: %d", encodedBytes);
    }

    return encodedBytes;
}

/**
 * Flush remaining MP3 data from encoder.
 * Returns number of bytes written to output buffer, or negative on error.
 */
JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeFlush(
    JNIEnv *env,
    jobject thiz,
    jlong lameHandle,
    jbyteArray mp3Buffer
) {
    if (lameHandle == 0) {
        LOGE("Invalid LAME handle");
        return -1;
    }

    lame_t lame = reinterpret_cast<lame_t>(lameHandle);

    // Get output buffer
    jbyte *mp3 = env->GetByteArrayElements(mp3Buffer, nullptr);
    if (mp3 == nullptr) {
        LOGE("Failed to get MP3 buffer");
        return -1;
    }

    jint mp3BufferSize = env->GetArrayLength(mp3Buffer);

    // Flush
    int flushedBytes = lame_encode_flush(
        lame,
        reinterpret_cast<unsigned char *>(mp3),
        mp3BufferSize
    );

    // Release array
    env->ReleaseByteArrayElements(mp3Buffer, mp3, 0);

    if (flushedBytes < 0) {
        LOGE("LAME flush failed: %d", flushedBytes);
    }

    return flushedBytes;
}

/**
 * Check if native LAME library is available.
 */
JNIEXPORT jboolean JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeIsAvailable(
    JNIEnv *env,
    jclass clazz
) {
    return JNI_TRUE;
}

/**
 * Get LAME version string.
 */
JNIEXPORT jstring JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeGetVersion(
    JNIEnv *env,
    jclass clazz
) {
    const char *version = get_lame_version();
    return env->NewStringUTF(version);
}

} // extern "C"
