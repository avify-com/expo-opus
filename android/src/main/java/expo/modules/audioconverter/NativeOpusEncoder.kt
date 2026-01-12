package expo.modules.audioconverter

import android.util.Log

/**
 * Native Opus Encoder wrapper
 *
 * This class provides JNI bindings to the native libopus library.
 * The native library is built from official Xiph.org sources using
 * scripts/build-opus-android.sh
 */
internal class NativeOpusEncoder private constructor(
  private val sampleRate: Int,
  private val channels: Int,
  private var encoderHandle: Long
) : AutoCloseable {

  companion object {
    private const val TAG = "NativeOpusEncoder"

    // Opus application modes
    const val APPLICATION_VOIP = 2048
    const val APPLICATION_AUDIO = 2049
    const val APPLICATION_RESTRICTED_LOWDELAY = 2051

    // Frame size: 20ms at 48kHz
    const val FRAME_SIZE = 960
    const val MAX_PACKET_SIZE = 4000

    private var libraryLoaded = false

    init {
      try {
        System.loadLibrary("opus_encoder")
        libraryLoaded = true
        Log.i(TAG, "Native Opus library loaded: ${nativeGetVersion()}")
      } catch (e: UnsatisfiedLinkError) {
        Log.w(TAG, "Native Opus library not available: ${e.message}")
        libraryLoaded = false
      }
    }

    /**
     * Check if native Opus encoding is available
     */
    fun isAvailable(): Boolean {
      if (!libraryLoaded) return false
      return try {
        nativeIsAvailable()
      } catch (e: Exception) {
        false
      }
    }

    /**
     * Get Opus library version string
     */
    fun getVersion(): String {
      return if (libraryLoaded) {
        try {
          nativeGetVersion()
        } catch (e: Exception) {
          "Unknown"
        }
      } else {
        "Not loaded"
      }
    }

    /**
     * Create a new Opus encoder
     *
     * @param sampleRate Sample rate (8000, 12000, 16000, 24000, 48000)
     * @param channels Number of channels (1 or 2)
     * @param application Application mode (VOIP, AUDIO, or RESTRICTED_LOWDELAY)
     * @param bitrate Target bitrate in bits per second
     */
    fun create(
      sampleRate: Int,
      channels: Int,
      application: Int = APPLICATION_VOIP,
      bitrate: Int = 64000
    ): NativeOpusEncoder {
      if (!isAvailable()) {
        throw OpusEncodingFailedException(
          "Native Opus library not available. Run scripts/build-opus-android.sh"
        )
      }

      val handle = nativeCreate(sampleRate, channels, application)
      if (handle == 0L) {
        throw OpusEncodingFailedException("Failed to create Opus encoder")
      }

      val encoder = NativeOpusEncoder(sampleRate, channels, handle)

      // Configure encoder
      encoder.setBitrate(bitrate)
      encoder.setComplexity(5) // Balanced for voice
      encoder.setVbr(true)

      return encoder
    }

    // Native methods
    @JvmStatic
    private external fun nativeIsAvailable(): Boolean

    @JvmStatic
    private external fun nativeGetVersion(): String

    @JvmStatic
    private external fun nativeCreate(sampleRate: Int, channels: Int, application: Int): Long
  }

  /**
   * Set encoder bitrate in bits per second
   */
  fun setBitrate(bitrate: Int) {
    checkNotClosed()
    val result = nativeSetBitrate(encoderHandle, bitrate)
    if (result < 0) {
      Log.w(TAG, "Failed to set bitrate: $result")
    }
  }

  /**
   * Set encoder complexity (0-10, higher = better quality, slower)
   */
  fun setComplexity(complexity: Int) {
    checkNotClosed()
    val result = nativeSetComplexity(encoderHandle, complexity.coerceIn(0, 10))
    if (result < 0) {
      Log.w(TAG, "Failed to set complexity: $result")
    }
  }

  /**
   * Enable or disable VBR (Variable Bit Rate)
   */
  fun setVbr(enabled: Boolean) {
    checkNotClosed()
    val result = nativeSetVbr(encoderHandle, if (enabled) 1 else 0)
    if (result < 0) {
      Log.w(TAG, "Failed to set VBR: $result")
    }
  }

  /**
   * Encode a frame of audio
   *
   * @param pcm PCM samples (interleaved if stereo)
   * @param frameSize Number of samples per channel (typically FRAME_SIZE = 960)
   * @return Encoded Opus packet, or null if encoding failed
   */
  fun encode(pcm: ShortArray, frameSize: Int = FRAME_SIZE): ByteArray? {
    checkNotClosed()

    val outputBuffer = ByteArray(MAX_PACKET_SIZE)
    val encodedBytes = nativeEncode(encoderHandle, pcm, frameSize, outputBuffer)

    return if (encodedBytes > 0) {
      outputBuffer.copyOf(encodedBytes)
    } else {
      Log.e(TAG, "Encode failed: $encodedBytes")
      null
    }
  }

  /**
   * Encode all samples into Opus packets
   *
   * @param samples All PCM samples (interleaved if stereo)
   * @return List of encoded Opus packets
   */
  fun encodeAll(samples: ShortArray): List<ByteArray> {
    checkNotClosed()

    val packets = mutableListOf<ByteArray>()
    val samplesPerFrame = FRAME_SIZE * channels
    var offset = 0

    while (offset + samplesPerFrame <= samples.size) {
      val frameSamples = samples.copyOfRange(offset, offset + samplesPerFrame)
      val packet = encode(frameSamples, FRAME_SIZE)
      if (packet != null) {
        packets.add(packet)
      }
      offset += samplesPerFrame
    }

    return packets
  }

  override fun close() {
    if (encoderHandle != 0L) {
      nativeDestroy(encoderHandle)
      encoderHandle = 0L
    }
  }

  private fun checkNotClosed() {
    if (encoderHandle == 0L) {
      throw IllegalStateException("Encoder has been closed")
    }
  }

  // Instance native methods
  private external fun nativeDestroy(handle: Long)
  private external fun nativeSetBitrate(handle: Long, bitrate: Int): Int
  private external fun nativeSetComplexity(handle: Long, complexity: Int): Int
  private external fun nativeSetVbr(handle: Long, vbr: Int): Int
  private external fun nativeEncode(handle: Long, pcm: ShortArray, frameSize: Int, output: ByteArray): Int
}
