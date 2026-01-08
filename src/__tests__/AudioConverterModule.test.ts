/**
 * Unit tests for AudioConverterModule
 */

import { mockNativeModule } from './__mocks__/expo-modules-core';
import {
  convertOpusToMp3,
  convertToOpus,
  isConversionSupported,
  isOpusEncodingSupported,
} from '../AudioConverterModule';
import type {
  AudioConversionResult,
  AudioInput,
  OpusConversionResult,
} from '../AudioConverter.types';

describe('AudioConverterModule', () => {
  describe('convertOpusToMp3', () => {
    const mockMp3Result: AudioConversionResult = {
      base64: 'bW9ja19tcDNfZGF0YQ==',
      durationMs: 5000,
      sizeBytes: 65536,
      mimeType: 'audio/mpeg',
    };

    beforeEach(() => {
      mockNativeModule.convertOpusToMp3Async.mockResolvedValue(mockMp3Result);
    });

    it('should convert base64 input with default options', async () => {
      const input: AudioInput = { type: 'base64', data: 'dGVzdF9kYXRh' };

      const result = await convertOpusToMp3(input);

      expect(result).toEqual(mockMp3Result);
      expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
        input,
        expect.objectContaining({ bitrate: 128 })
      );
    });

    it('should convert file URI input', async () => {
      const input: AudioInput = { type: 'uri', uri: 'file:///path/to/audio.ogg' };

      const result = await convertOpusToMp3(input);

      expect(result).toEqual(mockMp3Result);
      expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
        input,
        expect.objectContaining({ bitrate: 128 })
      );
    });

    describe('quality presets', () => {
      it('should map "low" quality to 64 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertOpusToMp3(input, { quality: 'low' });

        expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 64 })
        );
      });

      it('should map "medium" quality to 128 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertOpusToMp3(input, { quality: 'medium' });

        expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 128 })
        );
      });

      it('should map "high" quality to 192 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertOpusToMp3(input, { quality: 'high' });

        expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 192 })
        );
      });

      it('should map "best" quality to 320 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertOpusToMp3(input, { quality: 'best' });

        expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 320 })
        );
      });
    });

    describe('bitrate clamping', () => {
      it('should clamp bitrate below 64 to 64', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertOpusToMp3(input, { bitrate: 32 });

        expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 64 })
        );
      });

      it('should clamp bitrate above 320 to 320', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertOpusToMp3(input, { bitrate: 500 });

        expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 320 })
        );
      });

      it('should pass valid bitrate unchanged', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertOpusToMp3(input, { bitrate: 192 });

        expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 192 })
        );
      });
    });

    it('should prefer explicit bitrate over quality preset', async () => {
      const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

      await convertOpusToMp3(input, { quality: 'low', bitrate: 256 });

      expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
        input,
        expect.objectContaining({ bitrate: 256 })
      );
    });

    it('should pass sample rate option', async () => {
      const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

      await convertOpusToMp3(input, { sampleRate: 44100 });

      expect(mockNativeModule.convertOpusToMp3Async).toHaveBeenCalledWith(
        input,
        expect.objectContaining({ sampleRate: 44100 })
      );
    });

    it('should propagate native module errors', async () => {
      const error = new Error('Decoding failed');
      mockNativeModule.convertOpusToMp3Async.mockRejectedValue(error);

      const input: AudioInput = { type: 'base64', data: 'aW52YWxpZA==' };

      await expect(convertOpusToMp3(input)).rejects.toThrow('Decoding failed');
    });
  });

  describe('convertToOpus', () => {
    const mockOpusResult: OpusConversionResult = {
      base64: 'bW9ja19vcHVzX2RhdGE=',
      durationMs: 5000,
      sizeBytes: 32768,
      mimeType: 'audio/ogg',
      detectedFormat: 'mp3',
    };

    beforeEach(() => {
      mockNativeModule.convertToOpusAsync.mockResolvedValue(mockOpusResult);
    });

    it('should convert base64 input with default options', async () => {
      const input: AudioInput = { type: 'base64', data: 'bXAzX2RhdGE=' };

      const result = await convertToOpus(input);

      expect(result).toEqual(mockOpusResult);
      expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
        input,
        expect.objectContaining({
          bitrate: 64,
          sampleRate: 48000,
          sourceFormat: 'auto',
        })
      );
    });

    describe('quality presets', () => {
      it('should map "low" quality to 24 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertToOpus(input, { quality: 'low' });

        expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 24 })
        );
      });

      it('should map "medium" quality to 64 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertToOpus(input, { quality: 'medium' });

        expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 64 })
        );
      });

      it('should map "high" quality to 96 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertToOpus(input, { quality: 'high' });

        expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 96 })
        );
      });

      it('should map "best" quality to 128 kbps', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertToOpus(input, { quality: 'best' });

        expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 128 })
        );
      });
    });

    describe('bitrate clamping', () => {
      it('should clamp bitrate below 6 to 6', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertToOpus(input, { bitrate: 2 });

        expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 6 })
        );
      });

      it('should clamp bitrate above 510 to 510', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertToOpus(input, { bitrate: 600 });

        expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ bitrate: 510 })
        );
      });
    });

    describe('sample rate validation', () => {
      const validSampleRates = [8000, 12000, 16000, 24000, 48000];

      validSampleRates.forEach((sampleRate) => {
        it(`should accept valid sample rate ${sampleRate}`, async () => {
          const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

          await convertToOpus(input, { sampleRate });

          expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
            input,
            expect.objectContaining({ sampleRate })
          );
        });
      });

      it('should reset invalid sample rate to 48000', async () => {
        const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

        await convertToOpus(input, { sampleRate: 44100 });

        expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
          input,
          expect.objectContaining({ sampleRate: 48000 })
        );
      });
    });

    it('should pass channels option', async () => {
      const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

      await convertToOpus(input, { channels: 1 });

      expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
        input,
        expect.objectContaining({ channels: 1 })
      );
    });

    it('should pass source format hint', async () => {
      const input: AudioInput = { type: 'base64', data: 'dGVzdA==' };

      await convertToOpus(input, { sourceFormat: 'mp3' });

      expect(mockNativeModule.convertToOpusAsync).toHaveBeenCalledWith(
        input,
        expect.objectContaining({ sourceFormat: 'mp3' })
      );
    });

    it('should propagate native module errors', async () => {
      const error = new Error('Encoding failed');
      mockNativeModule.convertToOpusAsync.mockRejectedValue(error);

      const input: AudioInput = { type: 'base64', data: 'aW52YWxpZA==' };

      await expect(convertToOpus(input)).rejects.toThrow('Encoding failed');
    });
  });

  describe('isConversionSupported', () => {
    it('should return true when native module returns true', () => {
      mockNativeModule.isConversionSupported.mockReturnValue(true);

      expect(isConversionSupported()).toBe(true);
    });

    it('should return false when native module returns false', () => {
      mockNativeModule.isConversionSupported.mockReturnValue(false);

      expect(isConversionSupported()).toBe(false);
    });
  });

  describe('isOpusEncodingSupported', () => {
    it('should return true when native module returns true', () => {
      mockNativeModule.isOpusEncodingSupported.mockReturnValue(true);

      expect(isOpusEncodingSupported()).toBe(true);
    });

    it('should return false when native module returns false', () => {
      mockNativeModule.isOpusEncodingSupported.mockReturnValue(false);

      expect(isOpusEncodingSupported()).toBe(false);
    });
  });
});
