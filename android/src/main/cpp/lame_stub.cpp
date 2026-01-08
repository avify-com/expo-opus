#include <jni.h>
#include <android/log.h>

#define LOG_TAG "LameEncoderJNI"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/**
 * Stub implementation when libmp3lame.a is not available.
 * All functions return error values or throw exceptions.
 */

extern "C" {

JNIEXPORT jlong JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeCreate(
    JNIEnv *env, jobject thiz,
    jint inSampleRate, jint outSampleRate, jint channels, jint bitrate, jint quality
) {
    LOGE("LAME library not available - libmp3lame.a not built");
    return 0;
}

JNIEXPORT void JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeDestroy(
    JNIEnv *env, jobject thiz, jlong lameHandle
) {
    // No-op
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeEncodeInterleaved(
    JNIEnv *env, jobject thiz,
    jlong lameHandle, jshortArray pcmData, jint numSamples, jbyteArray mp3Buffer
) {
    LOGE("LAME library not available");
    return -1;
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeEncodeMono(
    JNIEnv *env, jobject thiz,
    jlong lameHandle, jshortArray pcmData, jint numSamples, jbyteArray mp3Buffer
) {
    LOGE("LAME library not available");
    return -1;
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeFlush(
    JNIEnv *env, jobject thiz, jlong lameHandle, jbyteArray mp3Buffer
) {
    LOGE("LAME library not available");
    return -1;
}

JNIEXPORT jboolean JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeIsAvailable(
    JNIEnv *env, jclass clazz
) {
    return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_expo_modules_audioconverter_NativeLameEncoder_nativeGetVersion(
    JNIEnv *env, jclass clazz
) {
    return env->NewStringUTF("LAME not available");
}

} // extern "C"
