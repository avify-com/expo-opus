export {
  convertOpusToMp3,
  convertToOpus,
  isConversionSupported,
  isOpusEncodingSupported,
} from './AudioConverterModule';

export type {
  AudioConversionError,
  AudioConversionOptions,
  AudioConversionResult,
  AudioInput,
  AudioQualityPreset,
  OpusConversionOptions,
  OpusConversionResult,
  SupportedAudioFormat,
} from './AudioConverter.types';

export { AudioConversionErrorCode } from './AudioConverter.types';
