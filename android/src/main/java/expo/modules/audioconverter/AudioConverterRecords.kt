package expo.modules.audioconverter

import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

/**
 * Input source for audio conversion
 */
class AudioInput : Record {
  @Field
  var type: String = "base64"

  @Field
  var data: String? = null

  @Field
  var uri: String? = null
}

/**
 * Options for audio conversion
 */
class ConversionOptions : Record {
  @Field
  var bitrate: Int = 128

  @Field
  var quality: String? = null

  @Field
  var sampleRate: Int? = null
}

/**
 * Result of audio conversion (Opus to MP3)
 */
class ConversionResult : Record {
  @Field
  var base64: String = ""

  @Field
  var durationMs: Int = 0

  @Field
  var sizeBytes: Int = 0

  @Field
  var mimeType: String = "audio/mpeg"

  constructor()

  constructor(base64: String, durationMs: Int, sizeBytes: Int) {
    this.base64 = base64
    this.durationMs = durationMs
    this.sizeBytes = sizeBytes
    this.mimeType = "audio/mpeg"
  }
}

/**
 * Options for Opus encoding
 */
class OpusConversionOptions : Record {
  @Field
  var bitrate: Int = 64

  @Field
  var quality: String? = null

  @Field
  var sampleRate: Int = 48000

  @Field
  var channels: Int? = null

  @Field
  var sourceFormat: String? = null
}

/**
 * Result of Opus conversion
 */
class OpusConversionResult : Record {
  @Field
  var base64: String = ""

  @Field
  var durationMs: Int = 0

  @Field
  var sizeBytes: Int = 0

  @Field
  var mimeType: String = "audio/ogg"

  @Field
  var detectedFormat: String = "auto"

  constructor()

  constructor(base64: String, durationMs: Int, sizeBytes: Int, detectedFormat: String) {
    this.base64 = base64
    this.durationMs = durationMs
    this.sizeBytes = sizeBytes
    this.mimeType = "audio/ogg"
    this.detectedFormat = detectedFormat
  }
}

/**
 * Internal structure for PCM audio data
 */
internal data class PCMData(
  val samples: ShortArray,
  val sampleRate: Int,
  val channels: Int,
  val durationMs: Int
) {
  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (javaClass != other?.javaClass) return false

    other as PCMData

    if (!samples.contentEquals(other.samples)) return false
    if (sampleRate != other.sampleRate) return false
    if (channels != other.channels) return false
    if (durationMs != other.durationMs) return false

    return true
  }

  override fun hashCode(): Int {
    var result = samples.contentHashCode()
    result = 31 * result + sampleRate
    result = 31 * result + channels
    result = 31 * result + durationMs
    return result
  }
}

/**
 * Internal structure for converted audio
 */
internal data class ConvertedAudio(
  val data: ByteArray,
  val durationMs: Int
) {
  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (javaClass != other?.javaClass) return false

    other as ConvertedAudio

    if (!data.contentEquals(other.data)) return false
    if (durationMs != other.durationMs) return false

    return true
  }

  override fun hashCode(): Int {
    var result = data.contentHashCode()
    result = 31 * result + durationMs
    return result
  }
}
