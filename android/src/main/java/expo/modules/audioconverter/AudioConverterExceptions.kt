package expo.modules.audioconverter

import expo.modules.kotlin.exception.CodedException

class InvalidInputException : CodedException(
  code = "INVALID_INPUT",
  message = "Invalid input data: must be valid base64 or file URI"
)

class UnsupportedFormatException : CodedException(
  code = "UNSUPPORTED_FORMAT",
  message = "Unsupported audio format: only OGG Opus is supported"
)

class DecodingFailedException(details: String) : CodedException(
  code = "DECODING_FAILED",
  message = "Failed to decode Opus audio: $details"
)

class EncodingFailedException(details: String) : CodedException(
  code = "ENCODING_FAILED",
  message = "Failed to encode MP3 audio: $details"
)

class FileNotFoundException(path: String) : CodedException(
  code = "FILE_NOT_FOUND",
  message = "File not found: $path"
)

class OutOfMemoryException : CodedException(
  code = "OUT_OF_MEMORY",
  message = "Out of memory during audio conversion"
)

class UnsupportedPlatformException : CodedException(
  code = "UNSUPPORTED_PLATFORM",
  message = "Audio conversion requires Android API 29 or higher"
)

class AudioDecodingFailedException(details: String) : CodedException(
  code = "AUDIO_DECODING_FAILED",
  message = "Failed to decode audio: $details"
)

class OpusEncodingFailedException(details: String) : CodedException(
  code = "OPUS_ENCODING_FAILED",
  message = "Failed to encode Opus audio: $details"
)

class UnsupportedSourceFormatException(details: String) : CodedException(
  code = "UNSUPPORTED_SOURCE_FORMAT",
  message = "Unsupported source format: $details"
)
