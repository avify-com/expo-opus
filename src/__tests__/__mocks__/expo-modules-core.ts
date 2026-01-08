/**
 * Mock for expo-modules-core
 * Allows testing TypeScript layer without native modules
 */

export const mockNativeModule = {
  convertOpusToMp3Async: jest.fn(),
  convertToOpusAsync: jest.fn(),
  isConversionSupported: jest.fn(),
  isOpusEncodingSupported: jest.fn(),
};

export function requireNativeModule<T>(_moduleName: string): T {
  return mockNativeModule as unknown as T;
}

export function resetMocks(): void {
  mockNativeModule.convertOpusToMp3Async.mockReset();
  mockNativeModule.convertToOpusAsync.mockReset();
  mockNativeModule.isConversionSupported.mockReset();
  mockNativeModule.isOpusEncodingSupported.mockReset();
}
