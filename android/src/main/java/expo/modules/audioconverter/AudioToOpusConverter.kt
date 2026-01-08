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
import java.util.zip.CRC32

/**
 * Audio to OGG/Opus Converter
 *
 * This class handles the conversion of audio files (MP3, AAC, M4A) to OGG/Opus format.
 * It uses Android MediaCodec for audio decoding and a pure Kotlin Opus encoder implementation.
 */
internal class AudioToOpusConverter(private val context: Context) {

  companion object {
    private const val TAG = "AudioToOpusConverter"
    private const val TIMEOUT_US = 10000L
    private const val FRAME_SIZE = 960 // 20ms at 48kHz
    private const val MAX_PACKET_SIZE = 4000
  }

  /**
   * Detected audio format
   */
  enum class DetectedFormat(val value: String) {
    MP3("mp3"),
    AAC("aac"),
    M4A("m4a"),
    UNKNOWN("unknown")
  }

  /**
   * Result of conversion including detected format
   */
  data class ConversionResult(
    val data: ByteArray,
    val durationMs: Int,
    val detectedFormat: DetectedFormat
  ) {
    override fun equals(other: Any?): Boolean {
      if (this === other) return true
      if (javaClass != other?.javaClass) return false
      other as ConversionResult
      if (!data.contentEquals(other.data)) return false
      if (durationMs != other.durationMs) return false
      if (detectedFormat != other.detectedFormat) return false
      return true
    }

    override fun hashCode(): Int {
      var result = data.contentHashCode()
      result = 31 * result + durationMs
      result = 31 * result + detectedFormat.hashCode()
      return result
    }
  }

  /**
   * Convert audio data to OGG/Opus
   *
   * @param inputData Raw audio data (MP3, AAC, or M4A)
   * @param bitrate Target Opus bitrate in kbps (6-510)
   * @param sampleRate Target sample rate (8000, 12000, 16000, 24000, 48000)
   * @param channels Optional target channel count (1 or 2)
   * @param sourceFormat Format hint ('auto' for auto-detection)
   * @return Converted audio data with OGG/Opus content
   */
  suspend fun convert(
    inputData: ByteArray,
    bitrate: Int,
    sampleRate: Int,
    channels: Int?,
    sourceFormat: String
  ): ConversionResult = withContext(Dispatchers.Default) {
    // Step 1: Detect source format
    val detectedFormat = detectFormat(inputData, sourceFormat)

    if (detectedFormat == DetectedFormat.UNKNOWN) {
      throw UnsupportedSourceFormatException("Could not detect audio format")
    }

    val tempFile = createTempFile(inputData, detectedFormat)

    try {
      // Step 2: Decode audio to PCM using MediaCodec
      val pcmData = decodeAudioToPcm(tempFile)

      // Step 3: Determine output parameters
      val outputChannels = channels ?: pcmData.channels
      val outputSampleRate = sampleRate

      // Step 4: Resample/remix if needed
      val processedPcm = resampleAudio(pcmData, outputSampleRate, outputChannels)

      // Step 5: Encode PCM to Opus
      val opusPackets = encodeToOpus(processedPcm, bitrate)

      // Step 6: Package into OGG container
      val oggData = createOggContainer(opusPackets, outputSampleRate, outputChannels)

      ConversionResult(
        data = oggData,
        durationMs = processedPcm.durationMs,
        detectedFormat = detectedFormat
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

  // MARK: - Format Detection

  /**
   * Detect audio format from magic bytes and hint
   */
  private fun detectFormat(data: ByteArray, hint: String): DetectedFormat {
    // If hint is provided and not 'auto', use it
    if (hint != "auto") {
      return when (hint.lowercase()) {
        "mp3" -> DetectedFormat.MP3
        "aac" -> DetectedFormat.AAC
        "m4a" -> DetectedFormat.M4A
        else -> detectFromMagicBytes(data)
      }
    }
    return detectFromMagicBytes(data)
  }

  /**
   * Detect format from magic bytes
   */
  private fun detectFromMagicBytes(data: ByteArray): DetectedFormat {
    if (data.size < 12) return DetectedFormat.UNKNOWN

    // Check for MP3 (ID3 tag or frame sync)
    if (data[0] == 0x49.toByte() && data[1] == 0x44.toByte() && data[2] == 0x33.toByte()) {
      return DetectedFormat.MP3 // ID3 tag
    }
    if (data[0] == 0xFF.toByte() && (data[1].toInt() and 0xE0) == 0xE0) {
      return DetectedFormat.MP3 // MP3 frame sync
    }

    // Check for M4A/AAC (ftyp box)
    if (data[4] == 0x66.toByte() && data[5] == 0x74.toByte() &&
      data[6] == 0x79.toByte() && data[7] == 0x70.toByte()
    ) {
      // Check specific ftyp brand
      val brand = String(data.sliceArray(8..11), Charsets.US_ASCII)
      return if (brand.startsWith("M4A")) {
        DetectedFormat.M4A
      } else {
        DetectedFormat.AAC
      }
    }

    // Check for AAC ADTS
    if (data[0] == 0xFF.toByte() && (data[1].toInt() and 0xF0) == 0xF0) {
      return DetectedFormat.AAC
    }

    return DetectedFormat.UNKNOWN
  }

  /**
   * Create a temporary file from byte array
   */
  private fun createTempFile(data: ByteArray, format: DetectedFormat): File {
    val extension = when (format) {
      DetectedFormat.MP3 -> ".mp3"
      DetectedFormat.AAC -> ".aac"
      DetectedFormat.M4A -> ".m4a"
      DetectedFormat.UNKNOWN -> ".audio"
    }
    val cacheDir = context.cacheDir
    val tempFile = File(cacheDir, "audio_${UUID.randomUUID()}$extension")
    tempFile.writeBytes(data)
    return tempFile
  }

  // MARK: - Audio Decoding (MediaCodec)

  /**
   * Decode audio file to PCM using Android MediaCodec
   */
  private fun decodeAudioToPcm(file: File): PCMData {
    val extractor = MediaExtractor()
    extractor.setDataSource(file.absolutePath)

    try {
      val trackIndex = findAudioTrack(extractor)
      if (trackIndex < 0) {
        throw AudioDecodingFailedException("No audio track found in file")
      }

      extractor.selectTrack(trackIndex)
      val format = extractor.getTrackFormat(trackIndex)
      Log.d(TAG, "Audio format: $format")

      val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
      val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
      val mime = format.getString(MediaFormat.KEY_MIME)
        ?: throw AudioDecodingFailedException("No MIME type in format")

      val decoder = MediaCodec.createDecoderByType(mime)
      decoder.configure(format, null, null, 0)
      decoder.start()

      try {
        val pcmBytes = decodeAudioData(extractor, decoder)

        if (pcmBytes.isEmpty()) {
          throw AudioDecodingFailedException("No audio samples decoded")
        }

        val samples = bytesToShorts(pcmBytes)
        // Use Long to prevent integer overflow for large audio files
        val durationMs = ((samples.size.toLong() / channels) * 1000 / sampleRate).toInt()

        return PCMData(
          samples = samples,
          sampleRate = sampleRate,
          channels = channels,
          durationMs = durationMs
        )
      } finally {
        decoder.stop()
        decoder.release()
      }
    } finally {
      extractor.release()
    }
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
   * Decode audio data from extractor
   */
  private fun decodeAudioData(extractor: MediaExtractor, decoder: MediaCodec): ByteArray {
    val pcmOutput = ByteArrayOutputStream()
    val bufferInfo = MediaCodec.BufferInfo()
    var inputDone = false
    var outputDone = false

    while (!outputDone) {
      if (!inputDone) {
        val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
        if (inputBufferIndex >= 0) {
          val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
          if (inputBuffer != null) {
            val sampleSize = extractor.readSampleData(inputBuffer, 0)

            if (sampleSize < 0) {
              decoder.queueInputBuffer(
                inputBufferIndex, 0, 0, 0,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM
              )
              inputDone = true
            } else {
              decoder.queueInputBuffer(
                inputBufferIndex, 0, sampleSize,
                extractor.sampleTime, 0
              )
              extractor.advance()
            }
          }
        }
      }

      val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
      if (outputBufferIndex >= 0) {
        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
        if (outputBuffer != null && bufferInfo.size > 0) {
          val chunk = ByteArray(bufferInfo.size)
          outputBuffer.get(chunk)
          pcmOutput.write(chunk)
        }
        decoder.releaseOutputBuffer(outputBufferIndex, false)

        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
          outputDone = true
        }
      }
    }

    return pcmOutput.toByteArray()
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

  // MARK: - Audio Resampling

  /**
   * Resample and remix audio to target parameters
   */
  private fun resampleAudio(
    pcmData: PCMData,
    targetSampleRate: Int,
    targetChannels: Int
  ): PCMData {
    var samples = pcmData.samples
    var currentSampleRate = pcmData.sampleRate
    var currentChannels = pcmData.channels

    // Channel conversion if needed
    if (currentChannels != targetChannels) {
      samples = convertChannels(samples, currentChannels, targetChannels)
      currentChannels = targetChannels
    }

    // Sample rate conversion if needed
    if (currentSampleRate != targetSampleRate) {
      samples = resampleSimple(samples, currentSampleRate, targetSampleRate, currentChannels)
      currentSampleRate = targetSampleRate
    }

    val durationMs = (samples.size / currentChannels) * 1000 / currentSampleRate

    return PCMData(
      samples = samples,
      sampleRate = currentSampleRate,
      channels = currentChannels,
      durationMs = durationMs
    )
  }

  /**
   * Convert between mono and stereo
   */
  private fun convertChannels(
    samples: ShortArray,
    fromChannels: Int,
    toChannels: Int
  ): ShortArray {
    if (fromChannels == toChannels) {
      return samples
    }

    if (fromChannels == 1 && toChannels == 2) {
      // Mono to stereo: duplicate samples
      val stereo = ShortArray(samples.size * 2)
      for (i in samples.indices) {
        stereo[i * 2] = samples[i]
        stereo[i * 2 + 1] = samples[i]
      }
      return stereo
    }

    if (fromChannels == 2 && toChannels == 1) {
      // Stereo to mono: average channels
      val mono = ShortArray(samples.size / 2)
      for (i in mono.indices) {
        val left = samples[i * 2].toInt()
        val right = samples[i * 2 + 1].toInt()
        mono[i] = ((left + right) / 2).toShort()
      }
      return mono
    }

    return samples
  }

  /**
   * Simple linear interpolation resampling
   */
  private fun resampleSimple(
    samples: ShortArray,
    fromRate: Int,
    toRate: Int,
    channels: Int
  ): ShortArray {
    val ratio = fromRate.toDouble() / toRate.toDouble()
    val inputFrames = samples.size / channels
    val outputFrames = (inputFrames / ratio).toInt()

    val resampled = ShortArray(outputFrames * channels)

    for (outFrame in 0 until outputFrames) {
      val inPos = outFrame * ratio
      val inFrame = inPos.toInt()
      val frac = (inPos - inFrame).toFloat()

      for (channel in 0 until channels) {
        val idx = inFrame * channels + channel
        val nextIdx = minOf((inFrame + 1) * channels + channel, samples.size - 1)

        val sample1 = samples[idx].toFloat()
        val sample2 = samples[nextIdx].toFloat()
        val interpolated = sample1 + frac * (sample2 - sample1)
        resampled[outFrame * channels + channel] =
          maxOf(-32768f, minOf(32767f, interpolated)).toInt().toShort()
      }
    }

    return resampled
  }

  // MARK: - Opus Encoding

  /**
   * Encode PCM to Opus packets using native libopus
   */
  private fun encodeToOpus(pcmData: PCMData, bitrate: Int): List<ByteArray> {
    if (!NativeOpusEncoder.isAvailable()) {
      throw OpusEncodingFailedException(
        "Native Opus encoder not available. Run scripts/build-opus-android.sh"
      )
    }

    val encoder = NativeOpusEncoder.create(
      sampleRate = pcmData.sampleRate,
      channels = pcmData.channels,
      application = NativeOpusEncoder.APPLICATION_VOIP,
      bitrate = bitrate * 1000  // Convert kbps to bps
    )

    return try {
      encoder.encodeAll(pcmData.samples)
    } catch (e: Exception) {
      Log.e(TAG, "Opus encoding failed", e)
      throw OpusEncodingFailedException("Opus encoding failed: ${e.message}")
    } finally {
      encoder.close()
    }
  }

  // MARK: - OGG Container Creation

  /**
   * Create OGG container with Opus packets
   */
  private fun createOggContainer(
    opusPackets: List<ByteArray>,
    sampleRate: Int,
    channels: Int
  ): ByteArray {
    val output = ByteArrayOutputStream()
    // Use UUID for cryptographically strong random serial number
    val serialNo = UUID.randomUUID().hashCode()
    var pageNo = 0
    var granulePos = 0L

    val preSkip = 312 // Default Opus pre-skip for 48kHz

    // Write OpusHead page (BOS - Beginning of Stream)
    val opusHead = createOpusHeadPacket(channels, sampleRate, preSkip)
    writeOggPage(output, opusHead, serialNo, pageNo++, 0, 0x02) // BOS flag

    // Write OpusTags page
    val opusTags = createOpusTagsPacket()
    writeOggPage(output, opusTags, serialNo, pageNo++, 0, 0x00)

    // Write audio pages
    for ((index, packet) in opusPackets.withIndex()) {
      granulePos += FRAME_SIZE
      val isLast = index == opusPackets.size - 1
      val headerType = if (isLast) 0x04 else 0x00 // EOS flag on last page

      writeOggPage(output, packet, serialNo, pageNo++, granulePos, headerType)
    }

    return output.toByteArray()
  }

  /**
   * Create OpusHead header packet
   */
  private fun createOpusHeadPacket(channels: Int, sampleRate: Int, preSkip: Int): ByteArray {
    val output = ByteArrayOutputStream()

    // Magic signature "OpusHead"
    output.write("OpusHead".toByteArray(Charsets.US_ASCII))

    // Version (1)
    output.write(1)

    // Channel count
    output.write(channels)

    // Pre-skip (little-endian)
    output.write(preSkip and 0xFF)
    output.write((preSkip shr 8) and 0xFF)

    // Input sample rate (little-endian)
    output.write(sampleRate and 0xFF)
    output.write((sampleRate shr 8) and 0xFF)
    output.write((sampleRate shr 16) and 0xFF)
    output.write((sampleRate shr 24) and 0xFF)

    // Output gain (0)
    output.write(0)
    output.write(0)

    // Channel mapping family (0 = mono/stereo)
    output.write(0)

    return output.toByteArray()
  }

  /**
   * Create OpusTags metadata packet
   */
  private fun createOpusTagsPacket(): ByteArray {
    val output = ByteArrayOutputStream()

    // Magic signature "OpusTags"
    output.write("OpusTags".toByteArray(Charsets.US_ASCII))

    // Vendor string
    val vendor = "expo-opus"
    val vendorBytes = vendor.toByteArray(Charsets.UTF_8)
    output.write(vendorBytes.size and 0xFF)
    output.write((vendorBytes.size shr 8) and 0xFF)
    output.write((vendorBytes.size shr 16) and 0xFF)
    output.write((vendorBytes.size shr 24) and 0xFF)
    output.write(vendorBytes)

    // Comment list length (0 comments)
    output.write(byteArrayOf(0, 0, 0, 0))

    return output.toByteArray()
  }

  /**
   * Write an OGG page
   */
  private fun writeOggPage(
    output: ByteArrayOutputStream,
    packet: ByteArray,
    serialNo: Int,
    pageNo: Int,
    granulePos: Long,
    headerType: Int
  ) {
    val page = ByteArrayOutputStream()

    // Capture pattern "OggS"
    page.write(byteArrayOf(0x4F, 0x67, 0x67, 0x53))

    // Stream structure version (0)
    page.write(0)

    // Header type flag
    page.write(headerType)

    // Granule position (little-endian)
    for (i in 0 until 8) {
      page.write(((granulePos shr (i * 8)) and 0xFF).toInt())
    }

    // Serial number (little-endian)
    for (i in 0 until 4) {
      page.write(((serialNo shr (i * 8)) and 0xFF))
    }

    // Page sequence number (little-endian)
    for (i in 0 until 4) {
      page.write(((pageNo shr (i * 8)) and 0xFF))
    }

    // CRC placeholder (will be filled later)
    val crcOffset = page.size()
    page.write(byteArrayOf(0, 0, 0, 0))

    // Segment table
    val segmentCount = (packet.size + 254) / 255
    page.write(segmentCount)

    var remaining = packet.size
    for (i in 0 until segmentCount) {
      val segmentSize = minOf(remaining, 255)
      page.write(segmentSize)
      remaining -= segmentSize
    }

    // Packet data
    page.write(packet)

    // Calculate and insert CRC
    val pageBytes = page.toByteArray()
    val crc = calculateOggCRC(pageBytes)
    pageBytes[crcOffset] = (crc and 0xFF).toByte()
    pageBytes[crcOffset + 1] = ((crc shr 8) and 0xFF).toByte()
    pageBytes[crcOffset + 2] = ((crc shr 16) and 0xFF).toByte()
    pageBytes[crcOffset + 3] = ((crc shr 24) and 0xFF).toByte()

    output.write(pageBytes)
  }

  /**
   * Calculate OGG CRC32
   */
  private fun calculateOggCRC(data: ByteArray): Long {
    var crc = 0L

    for (byte in data) {
      val index = ((crc shr 24) xor (byte.toLong() and 0xFF)).toInt() and 0xFF
      crc = ((crc shl 8) xor oggCrcTable[index]) and 0xFFFFFFFFL
    }

    return crc
  }

  /**
   * OGG CRC32 lookup table
   */
  private val oggCrcTable: LongArray by lazy {
    val table = LongArray(256)
    for (i in 0 until 256) {
      var r = i.toLong() shl 24
      for (j in 0 until 8) {
        r = if ((r and 0x80000000L) != 0L) {
          (r shl 1) xor 0x04C11DB7L
        } else {
          r shl 1
        }
      }
      table[i] = r and 0xFFFFFFFFL
    }
    table
  }
}
