# @avify-com/expo-opus

An Expo module for converting OGG/Opus audio files to MP3 format on iOS and Android. Perfect for apps that receive Opus audio (like WhatsApp voice messages) and need to play them on iOS, which doesn't natively support Opus.

## Features

- **OGG/Opus to MP3 conversion** - Convert Opus audio to widely-supported MP3 format
- **iOS & Android support** - Native implementations for both platforms
- **Base64 & File URI input** - Accept audio data as base64 string or file path
- **Quality presets** - Easy-to-use quality settings (low, medium, high, best)
- **Custom bitrate** - Fine-grained control over output quality (64-320 kbps)
- **Built from official sources** - Uses libopus from Xiph.org and LAME for encoding

## Installation

```bash
npx expo install @avify-com/expo-opus
```

### iOS Setup

After installing, run:

```bash
cd ios && pod install
```

The package includes pre-built `libopus.xcframework` and `libogg.xcframework` built from official [Xiph.org](https://xiph.org/) sources.

### Android Setup

No additional setup required. The package uses Android's MediaCodec for Opus decoding (requires API 29+) and includes the LAME encoder via the androLern library.

## Usage

### Basic Conversion

```typescript
import { convertOpusToMp3, isConversionSupported } from "@avify-com/expo-opus";

// Check if conversion is supported on this device
if (isConversionSupported()) {
  // Convert from base64
  const result = await convertOpusToMp3(
    { type: "base64", data: "T2dnUwACAAAAAAA..." },
    { quality: "medium" },
  );

  console.log("Converted MP3:", result.base64);
  console.log("Duration:", result.durationMs, "ms");
  console.log("Size:", result.sizeBytes, "bytes");
}
```

### Convert from File

```typescript
import { convertOpusToMp3 } from "@avify-com/expo-opus";

const result = await convertOpusToMp3(
  { type: "uri", uri: "file:///path/to/audio.ogg" },
  { bitrate: 192 },
);
```

### Quality Presets

```typescript
import { convertOpusToMp3 } from "@avify-com/expo-opus";

// Using quality presets
await convertOpusToMp3(input, { quality: "low" }); // 64 kbps
await convertOpusToMp3(input, { quality: "medium" }); // 128 kbps (default)
await convertOpusToMp3(input, { quality: "high" }); // 192 kbps
await convertOpusToMp3(input, { quality: "best" }); // 320 kbps

// Or specify exact bitrate
await convertOpusToMp3(input, { bitrate: 256 });
```

### With Custom Sample Rate

```typescript
import { convertOpusToMp3 } from "@avify-com/expo-opus";

const result = await convertOpusToMp3(
  { type: "uri", uri: audioPath },
  {
    quality: "high",
    sampleRate: 44100, // Output sample rate
  },
);
```

## API Reference

### `convertOpusToMp3(input, options?)`

Converts OGG/Opus audio to MP3 format.

#### Parameters

| Parameter | Type                     | Description                  |
| --------- | ------------------------ | ---------------------------- |
| `input`   | `AudioInput`             | The audio source (see below) |
| `options` | `AudioConversionOptions` | Optional conversion settings |

#### AudioInput

```typescript
type AudioInput =
  | { type: "base64"; data: string } // Base64-encoded OGG/Opus data
  | { type: "uri"; uri: string }; // File URI (file:// or absolute path)
```

#### AudioConversionOptions

| Property     | Type                                    | Default     | Description                             |
| ------------ | --------------------------------------- | ----------- | --------------------------------------- |
| `bitrate`    | `number`                                | `128`       | Target MP3 bitrate (64-320 kbps)        |
| `quality`    | `'low' \| 'medium' \| 'high' \| 'best'` | -           | Quality preset (overrides bitrate)      |
| `sampleRate` | `number`                                | source rate | Output sample rate (e.g., 44100, 48000) |

#### Returns

```typescript
interface AudioConversionResult {
  base64: string; // Base64-encoded MP3 data
  durationMs: number; // Duration in milliseconds
  sizeBytes: number; // Size of MP3 in bytes
  mimeType: "audio/mpeg"; // Always 'audio/mpeg'
}
```

### `isConversionSupported()`

Checks if audio conversion is supported on the current device.

```typescript
const supported = isConversionSupported();
// iOS: always true
// Android: true if API level >= 29 (Android 10+)
```

## Error Handling

The module throws typed errors that you can catch and handle:

```typescript
import {
  convertOpusToMp3,
  AudioConversionErrorCode,
} from "@avify-com/expo-opus";

try {
  const result = await convertOpusToMp3(input, options);
} catch (error) {
  switch (error.code) {
    case "INVALID_INPUT":
      console.error("Invalid input data");
      break;
    case "UNSUPPORTED_FORMAT":
      console.error("Not an OGG/Opus file");
      break;
    case "DECODING_FAILED":
      console.error("Failed to decode Opus audio");
      break;
    case "ENCODING_FAILED":
      console.error("Failed to encode MP3");
      break;
    case "FILE_NOT_FOUND":
      console.error("Input file not found");
      break;
    case "OUT_OF_MEMORY":
      console.error("Out of memory");
      break;
    default:
      console.error("Unknown error:", error.message);
  }
}
```

## Platform Support

| Platform | Minimum Version      | Notes                                                     |
| -------- | -------------------- | --------------------------------------------------------- |
| iOS      | 15.1+                | Uses vendored libopus/libogg xcframeworks + LAME CocoaPod |
| Android  | API 29+ (Android 10) | Uses MediaCodec for Opus + androLern for LAME             |

## Use Cases

- **WhatsApp voice messages** - WhatsApp sends voice messages as OGG/Opus, which iOS can't play natively
- **Telegram audio** - Telegram also uses Opus for voice messages
- **WebRTC recordings** - Opus is the default codec for WebRTC
- **Any Opus audio playback on iOS** - Convert once, cache, and play with expo-av

## Example: Caching Converted Audio

```typescript
import * as FileSystem from "expo-file-system";
import { convertOpusToMp3 } from "@avify-com/expo-opus";

async function convertAndCache(
  opusUri: string,
  cacheKey: string,
): Promise<string> {
  const cachePath = `${FileSystem.cacheDirectory}${cacheKey}.mp3`;

  // Check if already cached
  const info = await FileSystem.getInfoAsync(cachePath);
  if (info.exists) {
    return cachePath;
  }

  // Convert
  const result = await convertOpusToMp3(
    { type: "uri", uri: opusUri },
    { quality: "medium" },
  );

  // Save to cache
  await FileSystem.writeAsStringAsync(cachePath, result.base64, {
    encoding: FileSystem.EncodingType.Base64,
  });

  return cachePath;
}
```

## Technical Details

### iOS Implementation

- **OGG parsing**: Manual implementation reading OGG page structure
- **Opus decoding**: libopus 1.5.2 from Xiph.org (vendored xcframework)
- **MP3 encoding**: LAME via CocoaPod

### Android Implementation

- **OGG/Opus decoding**: Android MediaCodec (requires API 29+)
- **MP3 encoding**: LAME via androLern library

## Building from Source

The iOS xcframeworks are pre-built, but if you need to rebuild them:

```bash
cd modules/audio-converter/scripts
./build-opus-ios.sh
```

This downloads libopus and libogg from Xiph.org, verifies SHA256 checksums, and builds universal xcframeworks.

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request on [GitHub](https://github.com/avify-com/expo-opus).

## CI/CD & Releases

This project uses GitHub Actions for continuous integration and automated publishing. For detailed documentation on:

- **CI workflow** - Automated testing and native library builds
- **Publish workflow** - Publishing to GitHub Packages
- **Creating releases** - Step-by-step release process

See the [CI/CD Documentation](./docs/CI.md).

## Credits

- [libopus](https://opus-codec.org/) - Xiph.Org Foundation
- [libogg](https://xiph.org/ogg/) - Xiph.Org Foundation
- [LAME](https://lame.sourceforge.io/) - MP3 encoder
- [androLern](https://github.com/nicktgn/androLern) - Android LAME wrapper
