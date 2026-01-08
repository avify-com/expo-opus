#include <jni.h>
#include <android/log.h>
#include <opus/opus.h>
#include <cstring>
#include <vector>

#define LOG_TAG "OpusEncoderJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Frame size: 20ms at 48kHz = 960 samples
#define FRAME_SIZE 960
#define MAX_PACKET_SIZE 4000

extern "C" {

// Encoder handle stored as a long in Java
JNIEXPORT jlong JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeCreate(
    JNIEnv *env,
    jobject thiz,
    jint sampleRate,
    jint channels,
    jint application
) {
    int error;
    OpusEncoder *encoder = opus_encoder_create(sampleRate, channels, application, &error);

    if (error != OPUS_OK || encoder == nullptr) {
        LOGE("Failed to create Opus encoder: %d", error);
        return 0;
    }

    LOGI("Created Opus encoder: %dHz, %d channels", sampleRate, channels);
    return reinterpret_cast<jlong>(encoder);
}

JNIEXPORT void JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeDestroy(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle
) {
    if (encoderHandle != 0) {
        OpusEncoder *encoder = reinterpret_cast<OpusEncoder *>(encoderHandle);
        opus_encoder_destroy(encoder);
        LOGI("Destroyed Opus encoder");
    }
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeSetBitrate(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle,
    jint bitrate
) {
    if (encoderHandle == 0) return OPUS_INVALID_STATE;

    OpusEncoder *encoder = reinterpret_cast<OpusEncoder *>(encoderHandle);
    return opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeSetComplexity(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle,
    jint complexity
) {
    if (encoderHandle == 0) return OPUS_INVALID_STATE;

    OpusEncoder *encoder = reinterpret_cast<OpusEncoder *>(encoderHandle);
    return opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(complexity));
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeSetVbr(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle,
    jint vbr
) {
    if (encoderHandle == 0) return OPUS_INVALID_STATE;

    OpusEncoder *encoder = reinterpret_cast<OpusEncoder *>(encoderHandle);
    return opus_encoder_ctl(encoder, OPUS_SET_VBR(vbr));
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeEncode(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle,
    jshortArray pcmData,
    jint frameSize,
    jbyteArray outputBuffer
) {
    if (encoderHandle == 0) return OPUS_INVALID_STATE;

    OpusEncoder *encoder = reinterpret_cast<OpusEncoder *>(encoderHandle);

    // Get PCM samples
    jshort *pcm = env->GetShortArrayElements(pcmData, nullptr);
    if (pcm == nullptr) {
        LOGE("Failed to get PCM array");
        return OPUS_ALLOC_FAIL;
    }

    // Get output buffer
    jbyte *output = env->GetByteArrayElements(outputBuffer, nullptr);
    if (output == nullptr) {
        env->ReleaseShortArrayElements(pcmData, pcm, JNI_ABORT);
        LOGE("Failed to get output array");
        return OPUS_ALLOC_FAIL;
    }

    jint outputSize = env->GetArrayLength(outputBuffer);

    // Encode
    int encodedBytes = opus_encode(
        encoder,
        pcm,
        frameSize,
        reinterpret_cast<unsigned char *>(output),
        outputSize
    );

    // Release arrays
    env->ReleaseShortArrayElements(pcmData, pcm, JNI_ABORT);
    env->ReleaseByteArrayElements(outputBuffer, output, 0);

    if (encodedBytes < 0) {
        LOGE("Opus encode failed: %d", encodedBytes);
    }

    return encodedBytes;
}

JNIEXPORT jboolean JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeIsAvailable(
    JNIEnv *env,
    jclass clazz
) {
    // Native library is available if this function can be called
    return JNI_TRUE;
}

JNIEXPORT jstring JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeGetVersion(
    JNIEnv *env,
    jclass clazz
) {
    const char *version = opus_get_version_string();
    return env->NewStringUTF(version);
}

} // extern "C"
