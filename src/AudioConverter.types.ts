/**
 * Audio quality presets for encoding
 */
export type AudioQualityPreset = 'low' | 'medium' | 'high' | 'best';

/**
 * Supported source audio formats for Opus conversion
 */
export type SupportedAudioFormat = 'mp3' | 'aac' | 'm4a' | 'auto';

/**
 * Options for audio conversion
 */
export interface AudioConversionOptions {
  /**
   * Target MP3 bitrate in kbps (64-320)
   * @default 128
   */
  bitrate?: number;

  /**
   * Quality preset (overrides bitrate if set)
   * - low: 64 kbps
   * - medium: 128 kbps
   * - high: 192 kbps
   * - best: 320 kbps
   */
  quality?: AudioQualityPreset;

  /**
   * Sample rate for output (optional, uses source rate by default)
   * Common values: 44100, 48000
   */
  sampleRate?: number;
}

/**
 * Result of a successful audio conversion (Opus to MP3)
 */
export interface AudioConversionResult {
  /** Base64-encoded MP3 audio data */
  base64: string;

  /** Duration of the audio in milliseconds */
  durationMs: number;

  /** Size of the converted file in bytes */
  sizeBytes: number;

  /** MIME type of the output (always 'audio/mpeg') */
  mimeType: 'audio/mpeg';
}

/**
 * Options for converting audio to Opus format
 */
export interface OpusConversionOptions {
  /**
   * Target Opus bitrate in kbps (6-510)
   * Voice-optimized defaults: low=24, medium=64, high=96, best=128
   * @default 64
   */
  bitrate?: number;

  /**
   * Quality preset (overrides bitrate if set)
   * Voice-optimized mapping:
   * - low: 24 kbps
   * - medium: 64 kbps
   * - high: 96 kbps
   * - best: 128 kbps
   */
  quality?: AudioQualityPreset;

  /**
   * Output sample rate (8000, 12000, 16000, 24000, 48000)
   * @default 48000
   */
  sampleRate?: number;

  /**
   * Number of output channels (1 for mono, 2 for stereo)
   * If not specified, uses source channel count
   */
  channels?: 1 | 2;

  /**
   * Source format hint (auto-detected if not specified)
   * @default 'auto'
   */
  sourceFormat?: SupportedAudioFormat;
}

/**
 * Result of a successful conversion to Opus format
 */
export interface OpusConversionResult {
  /** Base64-encoded OGG/Opus audio data */
  base64: string;

  /** Duration of the audio in milliseconds */
  durationMs: number;

  /** Size of the converted file in bytes */
  sizeBytes: number;

  /** MIME type of the output (always 'audio/ogg') */
  mimeType: 'audio/ogg';

  /** Detected source format */
  detectedFormat: SupportedAudioFormat;
}

/**
 * Input source for audio conversion
 */
export type AudioInput =
  | { type: 'base64'; data: string }
  | { type: 'uri'; uri: string };

/**
 * Error codes for conversion failures
 */
export enum AudioConversionErrorCode {
  INVALID_INPUT = 'INVALID_INPUT',
  UNSUPPORTED_FORMAT = 'UNSUPPORTED_FORMAT',
  DECODING_FAILED = 'DECODING_FAILED',
  ENCODING_FAILED = 'ENCODING_FAILED',
  FILE_NOT_FOUND = 'FILE_NOT_FOUND',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  OUT_OF_MEMORY = 'OUT_OF_MEMORY',
  UNKNOWN = 'UNKNOWN',
  /** Failed to decode source audio (MP3, AAC, M4A) */
  AUDIO_DECODING_FAILED = 'AUDIO_DECODING_FAILED',
  /** Failed to encode to Opus format */
  OPUS_ENCODING_FAILED = 'OPUS_ENCODING_FAILED',
  /** Source format not supported for conversion */
  UNSUPPORTED_SOURCE_FORMAT = 'UNSUPPORTED_SOURCE_FORMAT',
}

/**
 * Error thrown when audio conversion fails
 */
export interface AudioConversionError extends Error {
  code: AudioConversionErrorCode;
}

/**
 * Native module interface
 */
export interface NativeAudioConverterModule {
  /** Convert Opus/OGG to MP3 */
  convertOpusToMp3Async(
    input: AudioInput,
    options: AudioConversionOptions
  ): Promise<AudioConversionResult>;

  /** Convert MP3/AAC/M4A to Opus/OGG */
  convertToOpusAsync(
    input: AudioInput,
    options: OpusConversionOptions
  ): Promise<OpusConversionResult>;

  /** Check if Opus to MP3 conversion is supported */
  isConversionSupported(): boolean;

  /** Check if encoding to Opus is supported */
  isOpusEncodingSupported(): boolean;
}
