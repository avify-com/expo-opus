package expo.modules.audioconverter

import android.content.Context
import android.os.Build
import android.util.Base64
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

private const val MAX_INPUT_SIZE = 50 * 1024 * 1024 // 50MB

class AudioConverterModule : Module() {

  private val context: Context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()

  private val opusToMp3Converter: OpusToMp3Converter by lazy {
    OpusToMp3Converter(context)
  }

  private val audioToOpusConverter: AudioToOpusConverter by lazy {
    AudioToOpusConverter(context)
  }

  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

  override fun definition() = ModuleDefinition {
    Name("ExpoAudioConverter")

    // Cancel coroutine scope when module is destroyed to prevent leaks
    OnDestroy {
      scope.cancel()
    }

    // Check if Opus to MP3 conversion is supported
    // MediaCodec Opus support requires API 29+
    Function("isConversionSupported") {
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    // Check if encoding to Opus is supported
    Function("isOpusEncodingSupported") {
      isOpusEncoderAvailable()
    }

    // Convert OGG Opus to MP3
    AsyncFunction("convertOpusToMp3Async") { input: AudioInput, options: ConversionOptions, promise: Promise ->
      if (!isApiLevelSupported()) {
        promise.reject(UnsupportedPlatformException())
        return@AsyncFunction
      }

      scope.launch {
        try {
          val inputData = extractInputData(input)
          validateInputData(inputData)

          val result = opusToMp3Converter.convert(
            inputData = inputData,
            bitrate = options.bitrate,
            sampleRate = options.sampleRate
          )

          val conversionResult = createConversionResult(result)
          promise.resolve(conversionResult)
        } catch (e: Exception) {
          handleConversionError(e, promise)
        }
      }
    }

    // Convert MP3/AAC/M4A to OGG Opus
    AsyncFunction("convertToOpusAsync") { input: AudioInput, options: OpusConversionOptions, promise: Promise ->
      if (!isApiLevelSupported()) {
        promise.reject(UnsupportedPlatformException())
        return@AsyncFunction
      }

      scope.launch {
        try {
          val inputData = extractInputData(input)
          validateInputData(inputData)

          val result = audioToOpusConverter.convert(
            inputData = inputData,
            bitrate = options.bitrate,
            sampleRate = options.sampleRate,
            channels = options.channels,
            sourceFormat = options.sourceFormat ?: "auto"
          )

          val conversionResult = createOpusConversionResult(result)
          promise.resolve(conversionResult)
        } catch (e: Exception) {
          handleOpusConversionError(e, promise)
        }
      }
    }
  }

  /**
   * Check if API level supports Opus decoding
   */
  private fun isApiLevelSupported(): Boolean {
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
  }

  /**
   * Extract input data from AudioInput
   */
  private fun extractInputData(input: AudioInput): ByteArray {
    return when (input.type) {
      "base64" -> extractBase64Data(input)
      "uri" -> extractUriData(input)
      else -> throw InvalidInputException()
    }
  }

  /**
   * Extract data from base64 input
   */
  private fun extractBase64Data(input: AudioInput): ByteArray {
    val base64Data = input.data ?: throw InvalidInputException()
    val cleanBase64 = cleanBase64String(base64Data)

    return try {
      Base64.decode(cleanBase64, Base64.DEFAULT)
    } catch (e: IllegalArgumentException) {
      throw InvalidInputException()
    }
  }

  /**
   * Clean base64 string by removing data URI prefix if present
   * Validates data URI format if present
   */
  private fun cleanBase64String(base64Data: String): String {
    if (base64Data.startsWith("data:")) {
      val parts = base64Data.split(",", limit = 2)
      if (parts.size != 2) {
        throw InvalidInputException()
      }
      val header = parts[0].lowercase()
      if (!header.contains("audio/") || !header.contains("base64")) {
        throw UnsupportedFormatException()
      }
      return parts[1]
    }
    return base64Data
  }

  /**
   * Extract data from URI input with path traversal protection
   */
  private fun extractUriData(input: AudioInput): ByteArray {
    val uriString = input.uri ?: throw InvalidInputException()
    val filePath = normalizeFilePath(uriString)
    val file = File(filePath).canonicalFile

    validateFilePath(file)

    if (!file.exists()) {
      throw FileNotFoundException(file.name)
    }

    return file.readBytes()
  }

  /**
   * Validate file path is within allowed directories (path traversal protection)
   */
  private fun validateFilePath(file: File) {
    val allowedDirs = listOf(
      context.cacheDir,
      context.filesDir,
      context.getExternalFilesDir(null)
    ).filterNotNull()

    val isAllowed = allowedDirs.any { dir ->
      file.path.startsWith(dir.canonicalPath)
    }

    if (!isAllowed) {
      throw InvalidInputException()
    }
  }

  /**
   * Normalize file path by removing file:// prefix if present
   */
  private fun normalizeFilePath(uriString: String): String {
    return if (uriString.startsWith("file://")) {
      uriString.removePrefix("file://")
    } else {
      uriString
    }
  }

  /**
   * Validate input data size (min 28 bytes for OGG header, max 50MB)
   */
  private fun validateInputData(inputData: ByteArray) {
    if (inputData.size < 28 || inputData.size > MAX_INPUT_SIZE) {
      throw InvalidInputException()
    }
  }

  /**
   * Create conversion result from converted audio
   */
  private fun createConversionResult(result: ConvertedAudio): ConversionResult {
    return ConversionResult(
      base64 = Base64.encodeToString(result.data, Base64.NO_WRAP),
      durationMs = result.durationMs,
      sizeBytes = result.data.size
    )
  }

  /**
   * Handle conversion errors
   */
  private fun handleConversionError(e: Exception, promise: Promise) {
    when (e) {
      is InvalidInputException -> promise.reject(e)
      is FileNotFoundException -> promise.reject(e)
      is DecodingFailedException -> promise.reject(e)
      is EncodingFailedException -> promise.reject(e)
      else -> promise.reject(
        DecodingFailedException(e.message ?: "Unknown error")
      )
    }
  }

  /**
   * Handle Opus conversion errors
   */
  private fun handleOpusConversionError(e: Exception, promise: Promise) {
    when (e) {
      is InvalidInputException -> promise.reject(e)
      is FileNotFoundException -> promise.reject(e)
      is AudioDecodingFailedException -> promise.reject(e)
      is OpusEncodingFailedException -> promise.reject(e)
      is UnsupportedSourceFormatException -> promise.reject(e)
      else -> promise.reject(
        AudioDecodingFailedException(e.message ?: "Unknown error")
      )
    }
  }

  /**
   * Check if Opus encoder is available (native libopus via JNI)
   */
  private fun isOpusEncoderAvailable(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      return false
    }
    return NativeOpusEncoder.isAvailable()
  }

  /**
   * Create Opus conversion result
   */
  private fun createOpusConversionResult(result: AudioToOpusConverter.ConversionResult): OpusConversionResult {
    return OpusConversionResult(
      base64 = Base64.encodeToString(result.data, Base64.NO_WRAP),
      durationMs = result.durationMs,
      sizeBytes = result.data.size,
      detectedFormat = result.detectedFormat.value
    )
  }
}
