package expo.modules.audioconverter

import android.util.Log

/**
 * Native LAME MP3 Encoder wrapper
 *
 * This class provides JNI bindings to the native libmp3lame library.
 * The native library is built from official SourceForge sources using
 * scripts/build-lame-android.sh
 */
internal class NativeLameEncoder private constructor(
  private val inSampleRate: Int,
  private val outSampleRate: Int,
  private val channels: Int,
  private val bitrate: Int,
  private var encoderHandle: Long
) : AutoCloseable {

  companion object {
    private const val TAG = "NativeLameEncoder"

    // Quality levels (0=best, 9=worst)
    const val QUALITY_BEST = 0
    const val QUALITY_HIGH = 2
    const val QUALITY_MEDIUM = 5
    const val QUALITY_LOW = 7

    // Recommended MP3 buffer size: 1.25 * num_samples + 7200
    const val FLUSH_BUFFER_SIZE = 7200

    private var libraryLoaded = false

    init {
      try {
        System.loadLibrary("lame_encoder")
        libraryLoaded = true
        Log.i(TAG, "Native LAME library loaded: ${nativeGetVersion()}")
      } catch (e: UnsatisfiedLinkError) {
        Log.w(TAG, "Native LAME library not available: ${e.message}")
        libraryLoaded = false
      }
    }

    /**
     * Check if native LAME encoding is available
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
     * Get LAME library version string
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
     * Create a new LAME encoder
     *
     * @param inSampleRate Input sample rate (e.g., 44100, 48000)
     * @param outSampleRate Output sample rate (e.g., 44100)
     * @param channels Number of channels (1 or 2)
     * @param bitrate Target bitrate in kbps (64-320)
     * @param quality Quality level (0=best, 9=worst)
     */
    fun create(
      inSampleRate: Int,
      outSampleRate: Int = inSampleRate,
      channels: Int,
      bitrate: Int,
      quality: Int = QUALITY_MEDIUM
    ): NativeLameEncoder {
      if (!isAvailable()) {
        throw EncodingFailedException(
          "Native LAME library not available. Run scripts/build-lame-android.sh"
        )
      }

      val handle = nativeCreate(inSampleRate, outSampleRate, channels, bitrate, quality)
      if (handle == 0L) {
        throw EncodingFailedException("Failed to create LAME encoder")
      }

      return NativeLameEncoder(inSampleRate, outSampleRate, channels, bitrate, handle)
    }

    /**
     * Calculate recommended MP3 buffer size for given number of samples
     */
    fun calculateBufferSize(numSamples: Int): Int {
      return ((1.25 * numSamples) + 7200).toInt()
    }

    // Native methods
    @JvmStatic
    private external fun nativeIsAvailable(): Boolean

    @JvmStatic
    private external fun nativeGetVersion(): String

    @JvmStatic
    private external fun nativeCreate(
      inSampleRate: Int,
      outSampleRate: Int,
      channels: Int,
      bitrate: Int,
      quality: Int
    ): Long
  }

  /**
   * Encode interleaved stereo PCM samples to MP3
   *
   * @param pcm Interleaved PCM samples (L,R,L,R,...)
   * @param numSamples Number of samples per channel
   * @return Encoded MP3 data, or null if encoding failed
   */
  fun encodeInterleaved(pcm: ShortArray, numSamples: Int): ByteArray? {
    checkNotClosed()

    val bufferSize = calculateBufferSize(numSamples)
    val mp3Buffer = ByteArray(bufferSize)

    val encodedBytes = nativeEncodeInterleaved(encoderHandle, pcm, numSamples, mp3Buffer)

    return if (encodedBytes >= 0) {
      if (encodedBytes > 0) mp3Buffer.copyOf(encodedBytes) else ByteArray(0)
    } else {
      Log.e(TAG, "Encode interleaved failed: $encodedBytes")
      null
    }
  }

  /**
   * Encode mono PCM samples to MP3
   *
   * @param pcm Mono PCM samples
   * @param numSamples Number of samples
   * @return Encoded MP3 data, or null if encoding failed
   */
  fun encodeMono(pcm: ShortArray, numSamples: Int): ByteArray? {
    checkNotClosed()

    val bufferSize = calculateBufferSize(numSamples)
    val mp3Buffer = ByteArray(bufferSize)

    val encodedBytes = nativeEncodeMono(encoderHandle, pcm, numSamples, mp3Buffer)

    return if (encodedBytes >= 0) {
      if (encodedBytes > 0) mp3Buffer.copyOf(encodedBytes) else ByteArray(0)
    } else {
      Log.e(TAG, "Encode mono failed: $encodedBytes")
      null
    }
  }

  /**
   * Flush remaining MP3 data from encoder
   *
   * @return Remaining MP3 data, or null if flush failed
   */
  fun flush(): ByteArray? {
    checkNotClosed()

    val mp3Buffer = ByteArray(FLUSH_BUFFER_SIZE)
    val flushedBytes = nativeFlush(encoderHandle, mp3Buffer)

    return if (flushedBytes >= 0) {
      if (flushedBytes > 0) mp3Buffer.copyOf(flushedBytes) else ByteArray(0)
    } else {
      Log.e(TAG, "Flush failed: $flushedBytes")
      null
    }
  }

  /**
   * Encode all samples to MP3
   *
   * @param samples All PCM samples (interleaved if stereo)
   * @return Complete MP3 data including flush
   */
  fun encodeAll(samples: ShortArray): ByteArray {
    checkNotClosed()

    val mp3Chunks = mutableListOf<ByteArray>()
    val samplesPerChannel = if (channels == 2) samples.size / 2 else samples.size

    // Encode samples
    val encoded = if (channels == 2) {
      encodeInterleaved(samples, samplesPerChannel)
    } else {
      encodeMono(samples, samplesPerChannel)
    }

    if (encoded != null && encoded.isNotEmpty()) {
      mp3Chunks.add(encoded)
    }

    // Flush remaining data
    val flushed = flush()
    if (flushed != null && flushed.isNotEmpty()) {
      mp3Chunks.add(flushed)
    }

    // Combine all chunks
    val totalSize = mp3Chunks.sumOf { it.size }
    val result = ByteArray(totalSize)
    var offset = 0
    for (chunk in mp3Chunks) {
      System.arraycopy(chunk, 0, result, offset, chunk.size)
      offset += chunk.size
    }

    return result
  }

  override fun close() {
    if (encoderHandle != 0L) {
      nativeDestroy(encoderHandle)
      encoderHandle = 0L
    }
  }

  private fun checkNotClosed() {
    if (encoderHandle == 0L) {
      throw IllegalStateException("LAME encoder has been closed")
    }
  }

  // Instance native methods
  private external fun nativeDestroy(handle: Long)

  private external fun nativeEncodeInterleaved(
    handle: Long,
    pcm: ShortArray,
    numSamples: Int,
    mp3Buffer: ByteArray
  ): Int

  private external fun nativeEncodeMono(
    handle: Long,
    pcm: ShortArray,
    numSamples: Int,
    mp3Buffer: ByteArray
  ): Int

  private external fun nativeFlush(handle: Long, mp3Buffer: ByteArray): Int
}
