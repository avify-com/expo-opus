#include <jni.h>
#include <android/log.h>

#define LOG_TAG "OpusEncoderJNI"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Stub implementation when libopus is not available
// All functions return error states or throw exceptions

extern "C" {

JNIEXPORT jlong JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeCreate(
    JNIEnv *env,
    jobject thiz,
    jint sampleRate,
    jint channels,
    jint application
) {
    LOGE("Native Opus library not available. Run scripts/build-opus-android.sh");
    return 0;
}

JNIEXPORT void JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeDestroy(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle
) {
    // No-op
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeSetBitrate(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle,
    jint bitrate
) {
    return -1;
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeSetComplexity(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle,
    jint complexity
) {
    return -1;
}

JNIEXPORT jint JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeSetVbr(
    JNIEnv *env,
    jobject thiz,
    jlong encoderHandle,
    jint vbr
) {
    return -1;
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
    return -1;
}

JNIEXPORT jboolean JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeIsAvailable(
    JNIEnv *env,
    jclass clazz
) {
    // Native library stub - Opus not available
    return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_expo_modules_audioconverter_NativeOpusEncoder_nativeGetVersion(
    JNIEnv *env,
    jclass clazz
) {
    return env->NewStringUTF("Not available - run build-opus-android.sh");
}

} // extern "C"
