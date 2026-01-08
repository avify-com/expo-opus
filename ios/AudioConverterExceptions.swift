import ExpoModulesCore

internal final class InvalidInputException: Exception {
  override var reason: String {
    "Invalid input data: must be valid base64 or file URI"
  }
}

internal final class UnsupportedFormatException: Exception {
  override var reason: String {
    "Unsupported audio format: only OGG Opus is supported"
  }
}

internal final class DecodingFailedException: GenericException<String> {
  override var reason: String {
    "Failed to decode Opus audio: \(param)"
  }
}

internal final class EncodingFailedException: GenericException<String> {
  override var reason: String {
    "Failed to encode MP3 audio: \(param)"
  }
}

internal final class FileNotFoundException: GenericException<String> {
  override var reason: String {
    "File not found: \(param)"
  }
}

internal final class OutOfMemoryException: Exception {
  override var reason: String {
    "Out of memory during audio conversion"
  }
}

internal final class AudioDecodingFailedException: GenericException<String> {
  override var reason: String {
    "Failed to decode audio: \(param)"
  }
}

internal final class OpusEncodingFailedException: GenericException<String> {
  override var reason: String {
    "Failed to encode Opus audio: \(param)"
  }
}

internal final class UnsupportedSourceFormatException: GenericException<String> {
  override var reason: String {
    "Unsupported source format: \(param)"
  }
}
