package expo.modules.audioconverter

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

/**
 * OGG Opus to MP3 Converter
 *
 * This class handles the conversion of OGG Opus audio files to MP3 format.
 * It uses Android MediaCodec for Opus decoding and a pure Java LAME implementation for MP3 encoding.
 */
internal class OpusToMp3Converter(private val context: Context) {

  companion object {
    private const val TAG = "OpusToMp3Converter"
    private const val TIMEOUT_US = 10000L
    private const val MP3_BUFFER_SIZE = 8192
  }

  /**
   * Convert OGG Opus audio data to MP3
   *
   * @param inputData Raw OGG Opus audio data
   * @param bitrate Target MP3 bitrate in kbps (64-320)
   * @param sampleRate Optional target sample rate
   * @return Converted audio data with MP3 content
   */
  suspend fun convert(
    inputData: ByteArray,
    bitrate: Int,
    sampleRate: Int?
  ): ConvertedAudio = withContext(Dispatchers.Default) {
    val tempFile = createTempFile(inputData)

    try {
      val pcmData = decodeOpusToPcm(tempFile)
      val targetSampleRate = sampleRate ?: pcmData.sampleRate
      val mp3Data = encodePcmToMp3(pcmData, bitrate, targetSampleRate)

      ConvertedAudio(
        data = mp3Data,
        durationMs = pcmData.durationMs
      )
    } finally {
      try {
        if (!tempFile.delete()) {
          Log.w(TAG, "Failed to delete temp file, scheduling for exit cleanup")
          tempFile.deleteOnExit()
        }
      } catch (e: SecurityException) {
        Log.e(TAG, "Security exception deleting temp file", e)
      }
    }
  }

  /**
   * Create a temporary file from byte array
   */
  private fun createTempFile(data: ByteArray): File {
    val cacheDir = context.cacheDir
    val tempFile = File(cacheDir, "opus_${UUID.randomUUID()}.ogg")
    tempFile.writeBytes(data)
    return tempFile
  }

  /**
   * Decode OGG Opus to PCM using Android MediaCodec
   */
  private fun decodeOpusToPcm(file: File): PCMData {
    val extractor = MediaExtractor()
    extractor.setDataSource(file.absolutePath)

    try {
      val trackIndex = findAudioTrack(extractor)
      val format = setupExtractor(extractor, trackIndex)
      val audioParams = extractAudioParams(format)

      val decoder = createDecoder(format)
      try {
        val pcmBytes = decodeAudioData(extractor, decoder)
        return createPCMData(pcmBytes, audioParams)
      } finally {
        decoder.stop()
        decoder.release()
      }
    } finally {
      extractor.release()
    }
  }

  /**
   * Setup media extractor and return format
   */
  private fun setupExtractor(extractor: MediaExtractor, trackIndex: Int): MediaFormat {
    if (trackIndex < 0) {
      throw DecodingFailedException("No audio track found in OGG file")
    }

    extractor.selectTrack(trackIndex)
    val format = extractor.getTrackFormat(trackIndex)
    Log.d(TAG, "Audio format: $format")
    return format
  }

  /**
   * Extract audio parameters from format
   */
  private fun extractAudioParams(format: MediaFormat): AudioParams {
    val mime = format.getString(MediaFormat.KEY_MIME)
      ?: throw DecodingFailedException("No MIME type in format")
    val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
    val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

    return AudioParams(mime, sampleRate, channels)
  }

  /**
   * Create and configure decoder
   */
  private fun createDecoder(format: MediaFormat): MediaCodec {
    val mime = format.getString(MediaFormat.KEY_MIME)
      ?: throw DecodingFailedException("No MIME type in format")
    val decoder = MediaCodec.createDecoderByType(mime)
    decoder.configure(format, null, null, 0)
    decoder.start()
    return decoder
  }

  /**
   * Decode audio data from extractor
   */
  private fun decodeAudioData(extractor: MediaExtractor, decoder: MediaCodec): ByteArray {
    val pcmOutput = ByteArrayOutputStream()
    val bufferInfo = MediaCodec.BufferInfo()
    var inputDone = false
    var outputDone = false

    while (!outputDone) {
      if (!inputDone) {
        inputDone = feedInputBuffer(extractor, decoder)
      }
      outputDone = processOutputBuffer(decoder, bufferInfo, pcmOutput)
    }

    return pcmOutput.toByteArray()
  }

  /**
   * Feed input buffer to decoder
   */
  private fun feedInputBuffer(extractor: MediaExtractor, decoder: MediaCodec): Boolean {
    val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
    if (inputBufferIndex < 0) return false

    val inputBuffer = decoder.getInputBuffer(inputBufferIndex) ?: return false
    val sampleSize = extractor.readSampleData(inputBuffer, 0)

    if (sampleSize < 0) {
      decoder.queueInputBuffer(
        inputBufferIndex,
        0,
        0,
        0,
        MediaCodec.BUFFER_FLAG_END_OF_STREAM
      )
      return true
    }

    decoder.queueInputBuffer(
      inputBufferIndex,
      0,
      sampleSize,
      extractor.sampleTime,
      0
    )
    extractor.advance()
    return false
  }

  /**
   * Process output buffer from decoder
   */
  private fun processOutputBuffer(
    decoder: MediaCodec,
    bufferInfo: MediaCodec.BufferInfo,
    output: ByteArrayOutputStream
  ): Boolean {
    val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
    if (outputBufferIndex < 0) return false

    val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
    if (outputBuffer != null && bufferInfo.size > 0) {
      val chunk = ByteArray(bufferInfo.size)
      outputBuffer.get(chunk)
      output.write(chunk)
    }
    decoder.releaseOutputBuffer(outputBufferIndex, false)

    return bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
  }

  /**
   * Create PCMData from decoded bytes
   */
  private fun createPCMData(pcmBytes: ByteArray, params: AudioParams): PCMData {
    if (pcmBytes.isEmpty()) {
      throw DecodingFailedException("No audio samples decoded")
    }

    val samples = bytesToShorts(pcmBytes)
    // Use Long to prevent integer overflow for large audio files
    val durationMs = ((samples.size.toLong() / params.channels) * 1000 / params.sampleRate).toInt()

    return PCMData(
      samples = samples,
      sampleRate = params.sampleRate,
      channels = params.channels,
      durationMs = durationMs
    )
  }

  /**
   * Find the audio track in the media extractor
   */
  private fun findAudioTrack(extractor: MediaExtractor): Int {
    for (i in 0 until extractor.trackCount) {
      val format = extractor.getTrackFormat(i)
      val mime = format.getString(MediaFormat.KEY_MIME)
      if (mime?.startsWith("audio/") == true) {
        return i
      }
    }
    return -1
  }

  /**
   * Convert byte array to short array (16-bit PCM)
   */
  private fun bytesToShorts(bytes: ByteArray): ShortArray {
    val shorts = ShortArray(bytes.size / 2)
    ByteBuffer.wrap(bytes)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asShortBuffer()
      .get(shorts)
    return shorts
  }

  /**
   * Encode PCM to MP3 using native LAME encoder
   *
   * Uses JNI bindings to official LAME library built from SourceForge sources.
   */
  private fun encodePcmToMp3(
    pcmData: PCMData,
    bitrate: Int,
    targetSampleRate: Int
  ): ByteArray {
    if (!NativeLameEncoder.isAvailable()) {
      throw EncodingFailedException(
        "Native LAME library not available. Run scripts/build-lame-android.sh"
      )
    }

    val encoder = NativeLameEncoder.create(
      inSampleRate = pcmData.sampleRate,
      outSampleRate = targetSampleRate,
      channels = pcmData.channels,
      bitrate = bitrate,
      quality = NativeLameEncoder.QUALITY_MEDIUM
    )

    return encoder.use { it.encodeAll(pcmData.samples) }
  }

  /**
   * Audio parameters data class
   */
  private data class AudioParams(
    val mime: String,
    val sampleRate: Int,
    val channels: Int
  )
}

