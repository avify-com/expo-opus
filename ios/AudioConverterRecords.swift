import ExpoModulesCore

/// Input source for audio conversion
internal struct AudioInput: Record {
  @Field
  var type: String = "base64"

  @Field
  var data: String?

  @Field
  var uri: String?
}

/// Options for audio conversion
internal struct ConversionOptions: Record {
  @Field
  var bitrate: Int = 128

  @Field
  var quality: String?

  @Field
  var sampleRate: Int?
}

/// Result of audio conversion (Opus to MP3)
internal struct ConversionResult: Record {
  @Field
  var base64: String = ""

  @Field
  var durationMs: Int = 0

  @Field
  var sizeBytes: Int = 0

  @Field
  var mimeType: String = "audio/mpeg"
}

/// Options for Opus encoding
internal struct OpusConversionOptions: Record {
  @Field
  var bitrate: Int = 64

  @Field
  var quality: String?

  @Field
  var sampleRate: Int = 48000

  @Field
  var channels: Int?

  @Field
  var sourceFormat: String?
}

/// Result of Opus conversion
internal struct OpusConversionResult: Record {
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
}

/// Internal structure for PCM audio data
internal struct PCMData {
  let samples: [Int16]
  let sampleRate: Int
  let channels: Int
  let durationMs: Int

  var data: Data {
    return samples.withUnsafeBufferPointer { buffer in
      Data(buffer: buffer)
    }
  }
}

/// Internal structure for converted audio
internal struct ConvertedAudio {
  let data: Data
  let durationMs: Int
}
