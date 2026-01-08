/**
 * Unit tests for Opus encoder logic
 *
 * These tests verify the pure C++ logic without JNI dependencies.
 * They can be run on the host machine during development.
 *
 * Build with: g++ -std=c++17 -DRUN_TESTS opus_encoder_test.cpp -o test_opus && ./test_opus
 */

#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>
#include <cstring>

// Test framework macros
#define TEST(name) void test_##name()
#define EXPECT_EQ(a, b) assert((a) == (b))
#define EXPECT_NE(a, b) assert((a) != (b))
#define EXPECT_TRUE(a) assert(a)
#define EXPECT_FALSE(a) assert(!(a))
#define EXPECT_GE(a, b) assert((a) >= (b))
#define EXPECT_LE(a, b) assert((a) <= (b))
#define RUN_TEST(name) do { \
    std::cout << "Running " #name "... "; \
    test_##name(); \
    std::cout << "PASSED" << std::endl; \
} while(0)

// Constants matching opus_encoder_jni.cpp
constexpr int OPUS_APPLICATION_VOIP = 2048;
constexpr int OPUS_APPLICATION_AUDIO = 2049;
constexpr int OPUS_APPLICATION_RESTRICTED_LOWDELAY = 2051;

constexpr int MIN_BITRATE = 6000;
constexpr int MAX_BITRATE = 510000;
constexpr int DEFAULT_FRAME_SIZE = 960;  // 20ms at 48kHz

// Valid Opus sample rates
constexpr int VALID_SAMPLE_RATES[] = {8000, 12000, 16000, 24000, 48000};
constexpr int NUM_VALID_SAMPLE_RATES = 5;

/**
 * Validate sample rate is supported by Opus
 */
bool isValidSampleRate(int sampleRate) {
    for (int i = 0; i < NUM_VALID_SAMPLE_RATES; i++) {
        if (VALID_SAMPLE_RATES[i] == sampleRate) {
            return true;
        }
    }
    return false;
}

/**
 * Validate channel count (Opus supports 1 or 2)
 */
bool isValidChannelCount(int channels) {
    return channels >= 1 && channels <= 2;
}

/**
 * Clamp bitrate to valid Opus range
 */
int clampBitrate(int bitrate) {
    if (bitrate < MIN_BITRATE) return MIN_BITRATE;
    if (bitrate > MAX_BITRATE) return MAX_BITRATE;
    return bitrate;
}

/**
 * Calculate frame size in samples for given sample rate and duration
 */
int calculateFrameSize(int sampleRate, int durationMs) {
    return sampleRate * durationMs / 1000;
}

/**
 * Calculate maximum encoded packet size
 * Opus recommends 4000 bytes for most applications
 */
int calculateMaxPacketSize() {
    return 4000;
}

/**
 * Calculate number of frames for given sample count
 */
int calculateFrameCount(int totalSamples, int channels, int frameSize) {
    int samplesPerFrame = frameSize * channels;
    return (totalSamples + samplesPerFrame - 1) / samplesPerFrame;
}

// ============================================================================
// Unit Tests
// ============================================================================

TEST(ValidSampleRates) {
    EXPECT_TRUE(isValidSampleRate(8000));
    EXPECT_TRUE(isValidSampleRate(12000));
    EXPECT_TRUE(isValidSampleRate(16000));
    EXPECT_TRUE(isValidSampleRate(24000));
    EXPECT_TRUE(isValidSampleRate(48000));
}

TEST(InvalidSampleRates) {
    EXPECT_FALSE(isValidSampleRate(0));
    EXPECT_FALSE(isValidSampleRate(-1));
    EXPECT_FALSE(isValidSampleRate(11025));
    EXPECT_FALSE(isValidSampleRate(22050));
    EXPECT_FALSE(isValidSampleRate(44100));
    EXPECT_FALSE(isValidSampleRate(96000));
}

TEST(ValidChannelCounts) {
    EXPECT_TRUE(isValidChannelCount(1));
    EXPECT_TRUE(isValidChannelCount(2));
}

TEST(InvalidChannelCounts) {
    EXPECT_FALSE(isValidChannelCount(0));
    EXPECT_FALSE(isValidChannelCount(-1));
    EXPECT_FALSE(isValidChannelCount(3));
    EXPECT_FALSE(isValidChannelCount(8));
}

TEST(BitrateClampingBelowMin) {
    EXPECT_EQ(clampBitrate(0), MIN_BITRATE);
    EXPECT_EQ(clampBitrate(1000), MIN_BITRATE);
    EXPECT_EQ(clampBitrate(5999), MIN_BITRATE);
}

TEST(BitrateClampingAtMin) {
    EXPECT_EQ(clampBitrate(MIN_BITRATE), MIN_BITRATE);
}

TEST(BitrateClampingInRange) {
    EXPECT_EQ(clampBitrate(64000), 64000);
    EXPECT_EQ(clampBitrate(128000), 128000);
    EXPECT_EQ(clampBitrate(256000), 256000);
}

TEST(BitrateClampingAtMax) {
    EXPECT_EQ(clampBitrate(MAX_BITRATE), MAX_BITRATE);
}

TEST(BitrateClampingAboveMax) {
    EXPECT_EQ(clampBitrate(510001), MAX_BITRATE);
    EXPECT_EQ(clampBitrate(600000), MAX_BITRATE);
    EXPECT_EQ(clampBitrate(1000000), MAX_BITRATE);
}

TEST(FrameSizeAt48kHz) {
    // 20ms at 48kHz = 960 samples
    EXPECT_EQ(calculateFrameSize(48000, 20), 960);
    // 10ms at 48kHz = 480 samples
    EXPECT_EQ(calculateFrameSize(48000, 10), 480);
    // 40ms at 48kHz = 1920 samples
    EXPECT_EQ(calculateFrameSize(48000, 40), 1920);
}

TEST(FrameSizeAt24kHz) {
    EXPECT_EQ(calculateFrameSize(24000, 20), 480);
}

TEST(FrameSizeAt16kHz) {
    EXPECT_EQ(calculateFrameSize(16000, 20), 320);
}

TEST(FrameSizeAt8kHz) {
    EXPECT_EQ(calculateFrameSize(8000, 20), 160);
}

TEST(MaxPacketSize) {
    int maxSize = calculateMaxPacketSize();
    EXPECT_GE(maxSize, 1000);  // Should be reasonably large
    EXPECT_LE(maxSize, 10000); // But not too large
}

TEST(FrameCountCalculation) {
    // 48000 samples, mono, 960 frame size = 50 frames
    EXPECT_EQ(calculateFrameCount(48000, 1, 960), 50);

    // 48000 samples, stereo, 960 frame size = 25 frames
    EXPECT_EQ(calculateFrameCount(48000, 2, 960), 25);

    // Partial frame should round up
    EXPECT_EQ(calculateFrameCount(1000, 1, 960), 2);
}

TEST(ApplicationModeConstants) {
    // These should match the Opus library constants
    EXPECT_EQ(OPUS_APPLICATION_VOIP, 2048);
    EXPECT_EQ(OPUS_APPLICATION_AUDIO, 2049);
    EXPECT_EQ(OPUS_APPLICATION_RESTRICTED_LOWDELAY, 2051);
}

TEST(DefaultFrameSize) {
    // Default should be 20ms at 48kHz
    EXPECT_EQ(DEFAULT_FRAME_SIZE, 960);
}

// ============================================================================
// Main test runner
// ============================================================================

#ifdef RUN_TESTS
int main() {
    std::cout << "Running Opus Encoder Unit Tests" << std::endl;
    std::cout << "================================" << std::endl;

    RUN_TEST(ValidSampleRates);
    RUN_TEST(InvalidSampleRates);
    RUN_TEST(ValidChannelCounts);
    RUN_TEST(InvalidChannelCounts);
    RUN_TEST(BitrateClampingBelowMin);
    RUN_TEST(BitrateClampingAtMin);
    RUN_TEST(BitrateClampingInRange);
    RUN_TEST(BitrateClampingAtMax);
    RUN_TEST(BitrateClampingAboveMax);
    RUN_TEST(FrameSizeAt48kHz);
    RUN_TEST(FrameSizeAt24kHz);
    RUN_TEST(FrameSizeAt16kHz);
    RUN_TEST(FrameSizeAt8kHz);
    RUN_TEST(MaxPacketSize);
    RUN_TEST(FrameCountCalculation);
    RUN_TEST(ApplicationModeConstants);
    RUN_TEST(DefaultFrameSize);

    std::cout << "================================" << std::endl;
    std::cout << "All tests passed!" << std::endl;
    return 0;
}
#endif
