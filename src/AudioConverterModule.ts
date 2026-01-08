import { requireNativeModule } from 'expo-modules-core';

import type {
  AudioConversionOptions,
  AudioConversionResult,
  AudioInput,
  AudioQualityPreset,
  NativeAudioConverterModule,
  OpusConversionOptions,
  OpusConversionResult,
} from './AudioConverter.types';

const NativeModule =
  requireNativeModule<NativeAudioConverterModule>('ExpoAudioConverter');

/**
 * Map quality preset to MP3 bitrate
 */
function qualityToMp3Bitrate(quality: AudioQualityPreset): number {
  switch (quality) {
    case 'low':
      return 64;
    case 'medium':
      return 128;
    case 'high':
      return 192;
    case 'best':
      return 320;
    default:
      return 128;
  }
}

/**
 * Map quality preset to Opus bitrate (voice-optimized)
 */
function qualityToOpusBitrate(quality: AudioQualityPreset): number {
  switch (quality) {
    case 'low':
      return 24;
    case 'medium':
      return 64;
    case 'high':
      return 96;
    case 'best':
      return 128;
    default:
      return 64;
  }
}

/**
 * Normalize MP3 conversion options
 */
function normalizeMp3Options(
  options: AudioConversionOptions = {}
): AudioConversionOptions {
  const normalized = { ...options };

  // If quality preset is provided, convert to bitrate
  if (normalized.quality && !normalized.bitrate) {
    normalized.bitrate = qualityToMp3Bitrate(normalized.quality);
  }

  // Default bitrate if not set
  if (!normalized.bitrate) {
    normalized.bitrate = 128;
  }

  // Clamp bitrate to valid MP3 range (64-320 kbps)
  normalized.bitrate = Math.max(64, Math.min(320, normalized.bitrate));

  return normalized;
}

/**
 * Valid Opus sample rates
 */
const VALID_OPUS_SAMPLE_RATES = [8000, 12000, 16000, 24000, 48000];

/**
 * Normalize Opus conversion options
 */
function normalizeOpusOptions(
  options: OpusConversionOptions = {}
): OpusConversionOptions {
  const normalized = { ...options };

  // If quality preset is provided, convert to bitrate
  if (normalized.quality && !normalized.bitrate) {
    normalized.bitrate = qualityToOpusBitrate(normalized.quality);
  }

  // Default bitrate if not set (64 kbps for voice)
  if (!normalized.bitrate) {
    normalized.bitrate = 64;
  }

  // Clamp bitrate to valid Opus range (6-510 kbps)
  normalized.bitrate = Math.max(6, Math.min(510, normalized.bitrate));

  // Default sample rate (48kHz is native Opus rate)
  if (!normalized.sampleRate) {
    normalized.sampleRate = 48000;
  }

  // Validate sample rate
  if (!VALID_OPUS_SAMPLE_RATES.includes(normalized.sampleRate)) {
    normalized.sampleRate = 48000;
  }

  // Default source format to auto-detect
  if (!normalized.sourceFormat) {
    normalized.sourceFormat = 'auto';
  }

  return normalized;
}

/**
 * Convert OGG Opus audio to MP3 format
 *
 * @param input - Audio input (base64 string or file URI)
 * @param options - Conversion options (bitrate, quality, sample rate)
 * @returns Promise with conversion result containing MP3 base64 data
 *
 * @example
 * ```typescript
 * // Convert from base64
 * const result = await convertOpusToMp3(
 *   { type: 'base64', data: 'SGVsbG8gV29ybGQ=' },
 *   { quality: 'medium' }
 * );
 *
 * // Convert from file URI
 * const result = await convertOpusToMp3(
 *   { type: 'uri', uri: 'file:///path/to/audio.ogg' },
 *   { bitrate: 192 }
 * );
 * ```
 */
export async function convertOpusToMp3(
  input: AudioInput,
  options: AudioConversionOptions = {}
): Promise<AudioConversionResult> {
  const normalizedOptions = normalizeMp3Options(options);
  return NativeModule.convertOpusToMp3Async(input, normalizedOptions);
}

/**
 * Check if Opus to MP3 conversion is supported on this platform
 *
 * @returns true if conversion is supported
 *
 * Note: iOS always supports conversion. Android requires API 29+ for MediaCodec Opus support.
 */
export function isConversionSupported(): boolean {
  return NativeModule.isConversionSupported();
}

/**
 * Convert audio (MP3, AAC, M4A) to OGG/Opus format
 *
 * @param input - Audio input (base64 string or file URI)
 * @param options - Conversion options (bitrate, quality, sample rate, channels)
 * @returns Promise with conversion result containing OGG/Opus base64 data
 *
 * @example
 * ```typescript
 * // Convert from base64
 * const result = await convertToOpus(
 *   { type: 'base64', data: 'SGVsbG8gV29ybGQ=' },
 *   { quality: 'medium' }
 * );
 *
 * // Convert from file URI (auto-detect format)
 * const result = await convertToOpus(
 *   { type: 'uri', uri: 'file:///path/to/audio.m4a' },
 *   { bitrate: 64 }
 * );
 *
 * console.log('Detected format:', result.detectedFormat);
 * ```
 */
export async function convertToOpus(
  input: AudioInput,
  options: OpusConversionOptions = {}
): Promise<OpusConversionResult> {
  const normalizedOptions = normalizeOpusOptions(options);
  return NativeModule.convertToOpusAsync(input, normalizedOptions);
}

/**
 * Check if encoding to Opus is supported on this platform
 *
 * @returns true if Opus encoding is supported
 *
 * Note: iOS always supports Opus encoding. Android requires the native Opus library.
 */
export function isOpusEncodingSupported(): boolean {
  return NativeModule.isOpusEncodingSupported();
}
