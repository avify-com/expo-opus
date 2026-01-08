import ExpoModulesCore

private let maxInputSize = 50 * 1024 * 1024 // 50MB

public class AudioConverterModule: Module {
  private let opusToMp3Converter = OpusToMp3Converter()
  private let audioToOpusConverter = AudioToOpusConverter()

  public func definition() -> ModuleDefinition {
    Name("ExpoAudioConverter")

    // Check if Opus to MP3 conversion is supported (always true on iOS)
    Function("isConversionSupported") {
      return true
    }

    // Check if encoding to Opus is supported (always true on iOS)
    Function("isOpusEncodingSupported") {
      return true
    }

    // Convert OGG Opus to MP3
    AsyncFunction("convertOpusToMp3Async") { (input: AudioInput, options: ConversionOptions) -> ConversionResult in
      let inputData = try extractInputData(from: input)
      try validateInputData(inputData)

      let result = try await self.opusToMp3Converter.convert(
        inputData: inputData,
        bitrate: options.bitrate,
        sampleRate: options.sampleRate
      )

      return createConversionResult(from: result)
    }

    // Convert MP3/AAC/M4A to OGG Opus
    AsyncFunction("convertToOpusAsync") { (input: AudioInput, options: OpusConversionOptions) -> OpusConversionResult in
      let inputData = try extractInputData(from: input)
      try validateInputData(inputData)

      let result = try await self.audioToOpusConverter.convert(
        inputData: inputData,
        bitrate: options.bitrate,
        sampleRate: options.sampleRate,
        channels: options.channels,
        sourceFormat: options.sourceFormat ?? "auto"
      )

      return createOpusConversionResult(from: result)
    }
  }

  /// Extract input data from AudioInput
  private func extractInputData(from input: AudioInput) throws -> Data {
    switch input.type {
    case "base64":
      return try extractBase64Data(from: input)
    case "uri":
      return try extractUriData(from: input)
    default:
      throw InvalidInputException()
    }
  }

  /// Extract data from base64 input with data URI validation
  private func extractBase64Data(from input: AudioInput) throws -> Data {
    guard let base64Data = input.data else {
      throw InvalidInputException()
    }

    let cleanBase64 = try cleanBase64String(base64Data)

    guard let data = Data(base64Encoded: cleanBase64) else {
      throw InvalidInputException()
    }

    return data
  }

  /// Clean base64 string and validate data URI format if present
  private func cleanBase64String(_ base64Data: String) throws -> String {
    if base64Data.hasPrefix("data:") {
      let parts = base64Data.split(separator: ",", maxSplits: 1)
      guard parts.count == 2 else {
        throw InvalidInputException()
      }
      let header = String(parts[0]).lowercased()
      guard header.contains("audio/") && header.contains("base64") else {
        throw UnsupportedFormatException()
      }
      return String(parts[1])
    }
    return base64Data
  }

  /// Extract data from URI input with path traversal protection
  private func extractUriData(from input: AudioInput) throws -> Data {
    guard let uriString = input.uri else {
      throw InvalidInputException()
    }

    let filePath = normalizeFilePath(uriString)
    let url = URL(fileURLWithPath: filePath)
    let resolvedURL = url.resolvingSymlinksInPath()

    try validateFilePath(resolvedURL)

    guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
      throw FileNotFoundException(resolvedURL.lastPathComponent)
    }

    guard let data = FileManager.default.contents(atPath: resolvedURL.path) else {
      throw DecodingFailedException("Could not read file")
    }

    return data
  }

  /// Validate file path is within allowed directories (path traversal protection)
  private func validateFilePath(_ url: URL) throws {
    let allowedDirs = [
      FileManager.default.temporaryDirectory,
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    ].compactMap { $0 }

    let isAllowed = allowedDirs.contains { dir in
      url.path.hasPrefix(dir.path)
    }

    guard isAllowed else {
      throw InvalidInputException()
    }
  }

  /// Normalize file path by removing file:// prefix if present
  private func normalizeFilePath(_ uriString: String) -> String {
    if uriString.hasPrefix("file://") {
      return String(uriString.dropFirst(7))
    }
    return uriString
  }

  /// Validate input data size (min 28 bytes for OGG header, max 50MB)
  private func validateInputData(_ inputData: Data) throws {
    guard inputData.count >= 28 && inputData.count <= maxInputSize else {
      throw InvalidInputException()
    }
  }

  /// Create conversion result from converted audio
  private func createConversionResult(from result: ConvertedAudio) -> ConversionResult {
    return ConversionResult(
      base64: result.data.base64EncodedString(),
      durationMs: result.durationMs,
      sizeBytes: result.data.count,
      mimeType: "audio/mpeg"
    )
  }

  /// Create Opus conversion result
  private func createOpusConversionResult(from result: AudioToOpusConverter.ConversionResult) -> OpusConversionResult {
    return OpusConversionResult(
      base64: result.data.base64EncodedString(),
      durationMs: result.durationMs,
      sizeBytes: result.data.count,
      mimeType: "audio/ogg",
      detectedFormat: result.detectedFormat.rawValue
    )
  }
}
