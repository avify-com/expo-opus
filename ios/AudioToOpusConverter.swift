import AVFoundation
import Foundation
import ogg
import opus

/// Audio to OGG/Opus Converter
///
/// This class handles the conversion of audio files (MP3, AAC, M4A) to OGG/Opus format.
/// It uses AVFoundation for audio decoding and libopus for Opus encoding.
internal class AudioToOpusConverter {

  // MARK: - Constants

  private static let frameSize = 960  // 20ms at 48kHz (recommended Opus frame)
  private static let maxPacketSize = 4000  // Maximum Opus packet size

  // MARK: - Types

  /// Detected audio format
  enum DetectedFormat: String {
    case mp3
    case aac
    case m4a
    case unknown
  }

  /// Result of conversion including detected format
  struct ConversionResult {
    let data: Data
    let durationMs: Int
    let detectedFormat: DetectedFormat
  }

  // MARK: - Public Methods

  /// Convert audio data to OGG/Opus
  /// - Parameters:
  ///   - inputData: Raw audio data (MP3, AAC, or M4A)
  ///   - bitrate: Target Opus bitrate in kbps (6-510)
  ///   - sampleRate: Target sample rate (8000, 12000, 16000, 24000, 48000)
  ///   - channels: Optional target channel count (1 or 2)
  ///   - sourceFormat: Format hint ('auto' for auto-detection)
  /// - Returns: Converted audio data with OGG/Opus content
  func convert(
    inputData: Data,
    bitrate: Int,
    sampleRate: Int,
    channels: Int?,
    sourceFormat: String
  ) async throws -> ConversionResult {
    // Step 1: Detect source format
    let detectedFormat = detectFormat(data: inputData, hint: sourceFormat)

    guard detectedFormat != .unknown else {
      throw UnsupportedSourceFormatException("Could not detect audio format")
    }

    // Step 2: Decode audio to PCM using AVFoundation
    let pcmData = try await decodeAudioToPCM(data: inputData)

    // Step 3: Determine output parameters
    let outputChannels = channels ?? pcmData.channels
    let outputSampleRate = sampleRate

    // Step 4: Resample/remix if needed
    let processedPCM = try resampleAudio(
      pcmData: pcmData,
      targetSampleRate: outputSampleRate,
      targetChannels: outputChannels
    )

    // Step 5: Encode PCM to Opus
    let opusPackets = try encodeToOpus(
      pcmData: processedPCM,
      bitrate: bitrate
    )

    // Step 6: Package into OGG container
    let oggData = try createOggContainer(
      opusPackets: opusPackets,
      sampleRate: outputSampleRate,
      channels: outputChannels
    )

    return ConversionResult(
      data: oggData,
      durationMs: processedPCM.durationMs,
      detectedFormat: detectedFormat
    )
  }

  // MARK: - Format Detection

  /// Detect audio format from magic bytes and hint
  private func detectFormat(data: Data, hint: String) -> DetectedFormat {
    // If hint is provided and not 'auto', use it
    if hint != "auto" {
      switch hint.lowercased() {
      case "mp3": return .mp3
      case "aac": return .aac
      case "m4a": return .m4a
      default: break
      }
    }

    // Auto-detect from magic bytes
    guard data.count >= 12 else { return .unknown }

    // Check for MP3 (ID3 tag or frame sync)
    if data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33 {
      return .mp3  // ID3 tag
    }
    if data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
      return .mp3  // MP3 frame sync
    }

    // Check for M4A/AAC (ftyp box)
    if data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
      // Check specific ftyp brand
      let brand = String(data: data[8..<12], encoding: .ascii) ?? ""
      if brand.hasPrefix("M4A") {
        return .m4a
      }
      return .aac
    }

    // Check for AAC ADTS
    if data[0] == 0xFF && (data[1] & 0xF0) == 0xF0 {
      return .aac
    }

    return .unknown
  }

  // MARK: - Audio Decoding (AVFoundation)

  /// Decode audio file to PCM using AVFoundation
  private func decodeAudioToPCM(data: Data) async throws -> PCMData {
    // Write to temp file for AVAudioFile
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".audio")

    try data.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Use AVAudioFile to read audio
    let audioFile: AVAudioFile
    do {
      audioFile = try AVAudioFile(forReading: tempURL)
    } catch {
      throw AudioDecodingFailedException("Could not open audio file: \(error.localizedDescription)")
    }

    let format = audioFile.processingFormat
    let frameCount = AVAudioFrameCount(audioFile.length)

    guard frameCount > 0 else {
      throw AudioDecodingFailedException("Audio file is empty")
    }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      throw AudioDecodingFailedException("Could not create audio buffer")
    }

    do {
      try audioFile.read(into: buffer)
    } catch {
      throw AudioDecodingFailedException("Could not read audio data: \(error.localizedDescription)")
    }

    // Convert to Int16 samples
    let samples = try convertToInt16Samples(buffer: buffer)
    let durationMs = Int(Double(frameCount) / format.sampleRate * 1000)

    return PCMData(
      samples: samples,
      sampleRate: Int(format.sampleRate),
      channels: Int(format.channelCount),
      durationMs: durationMs
    )
  }

  /// Convert AVAudioPCMBuffer to Int16 samples
  private func convertToInt16Samples(buffer: AVAudioPCMBuffer) throws -> [Int16] {
    guard let floatData = buffer.floatChannelData else {
      throw AudioDecodingFailedException("Could not access audio sample data")
    }

    let frameLength = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    var samples: [Int16] = []
    samples.reserveCapacity(frameLength * channelCount)

    // Interleave channels and convert float to Int16
    for frame in 0..<frameLength {
      for channel in 0..<channelCount {
        let floatSample = floatData[channel][frame]
        // Clamp and convert to Int16
        let clampedSample = max(-1.0, min(1.0, floatSample))
        let int16Sample = Int16(clampedSample * Float(Int16.max))
        samples.append(int16Sample)
      }
    }

    return samples
  }

  // MARK: - Audio Resampling

  /// Resample and remix audio to target parameters
  private func resampleAudio(
    pcmData: PCMData,
    targetSampleRate: Int,
    targetChannels: Int
  ) throws -> PCMData {
    var samples = pcmData.samples
    var currentSampleRate = pcmData.sampleRate
    var currentChannels = pcmData.channels

    // Channel conversion if needed
    if currentChannels != targetChannels {
      samples = convertChannels(
        samples: samples,
        fromChannels: currentChannels,
        toChannels: targetChannels
      )
      currentChannels = targetChannels
    }

    // Sample rate conversion if needed
    if currentSampleRate != targetSampleRate {
      samples = resampleSimple(
        samples: samples,
        fromRate: currentSampleRate,
        toRate: targetSampleRate,
        channels: currentChannels
      )
      currentSampleRate = targetSampleRate
    }

    // Use Int64 to prevent integer overflow for large audio files
    let durationMs = Int((Int64(samples.count) / Int64(currentChannels)) * 1000 / Int64(currentSampleRate))

    return PCMData(
      samples: samples,
      sampleRate: currentSampleRate,
      channels: currentChannels,
      durationMs: durationMs
    )
  }

  /// Convert between mono and stereo
  private func convertChannels(
    samples: [Int16],
    fromChannels: Int,
    toChannels: Int
  ) -> [Int16] {
    if fromChannels == toChannels {
      return samples
    }

    if fromChannels == 1 && toChannels == 2 {
      // Mono to stereo: duplicate samples
      var stereo: [Int16] = []
      stereo.reserveCapacity(samples.count * 2)
      for sample in samples {
        stereo.append(sample)
        stereo.append(sample)
      }
      return stereo
    }

    if fromChannels == 2 && toChannels == 1 {
      // Stereo to mono: average channels
      var mono: [Int16] = []
      mono.reserveCapacity(samples.count / 2)
      for i in stride(from: 0, to: samples.count - 1, by: 2) {
        let left = Int32(samples[i])
        let right = Int32(samples[i + 1])
        let mixed = Int16((left + right) / 2)
        mono.append(mixed)
      }
      return mono
    }

    return samples
  }

  /// Simple linear interpolation resampling
  private func resampleSimple(
    samples: [Int16],
    fromRate: Int,
    toRate: Int,
    channels: Int
  ) -> [Int16] {
    let ratio = Double(fromRate) / Double(toRate)
    let inputFrames = samples.count / channels
    let outputFrames = Int(Double(inputFrames) / ratio)

    var resampled: [Int16] = []
    resampled.reserveCapacity(outputFrames * channels)

    for outFrame in 0..<outputFrames {
      let inPos = Double(outFrame) * ratio
      let inFrame = Int(inPos)
      let frac = Float(inPos - Double(inFrame))

      for channel in 0..<channels {
        let idx = inFrame * channels + channel
        let nextIdx = min((inFrame + 1) * channels + channel, samples.count - 1)

        let sample1 = Float(samples[idx])
        let sample2 = Float(samples[nextIdx])
        let interpolated = sample1 + frac * (sample2 - sample1)
        resampled.append(Int16(max(-32768, min(32767, interpolated))))
      }
    }

    return resampled
  }

  // MARK: - Opus Encoding

  /// Encode PCM to Opus packets
  private func encodeToOpus(pcmData: PCMData, bitrate: Int) throws -> [Data] {
    // Create encoder with VOIP application mode (optimized for voice)
    var error: Int32 = 0
    guard let encoder = opus_encoder_create(
      Int32(pcmData.sampleRate),
      Int32(pcmData.channels),
      OPUS_APPLICATION_VOIP,
      &error
    ) else {
      throw OpusEncodingFailedException("Failed to create Opus encoder: \(error)")
    }

    defer { opus_encoder_destroy(encoder) }

    guard error == OPUS_OK else {
      throw OpusEncodingFailedException("Opus encoder initialization failed: \(error)")
    }

    // Configure encoder
    opus_encoder_ctl(encoder, OPUS_SET_BITRATE_REQUEST, Int32(bitrate * 1000))
    opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY_REQUEST, Int32(5))  // Balanced for voice
    opus_encoder_ctl(encoder, OPUS_SET_VBR_REQUEST, Int32(1))  // Enable VBR for voice

    // Encode frames
    var packets: [Data] = []
    let samplesPerFrame = Self.frameSize * pcmData.channels
    var offset = 0

    let packetBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.maxPacketSize)
    defer { packetBuffer.deallocate() }

    while offset + samplesPerFrame <= pcmData.samples.count {
      let frameSamples = Array(pcmData.samples[offset..<(offset + samplesPerFrame)])
      let packet = try encodeFrame(
        encoder: encoder,
        samples: frameSamples,
        channels: pcmData.channels,
        packetBuffer: packetBuffer
      )
      packets.append(packet)
      offset += samplesPerFrame
    }

    guard !packets.isEmpty else {
      throw OpusEncodingFailedException("No audio frames encoded")
    }

    return packets
  }

  /// Encode a single frame to Opus
  private func encodeFrame(
    encoder: OpaquePointer,
    samples: [Int16],
    channels: Int,
    packetBuffer: UnsafeMutablePointer<UInt8>
  ) throws -> Data {
    let encodedBytes = samples.withUnsafeBufferPointer { samplesPtr in
      opus_encode(
        encoder,
        samplesPtr.baseAddress,
        Int32(Self.frameSize),
        packetBuffer,
        Int32(Self.maxPacketSize)
      )
    }

    guard encodedBytes > 0 else {
      throw OpusEncodingFailedException("Opus encode failed with code: \(encodedBytes)")
    }

    return Data(bytes: packetBuffer, count: Int(encodedBytes))
  }

  // MARK: - OGG Container Creation

  /// Create OGG container with Opus packets
  private func createOggContainer(
    opusPackets: [Data],
    sampleRate: Int,
    channels: Int
  ) throws -> Data {
    var oggOutput = Data()
    var serialNo = Int32.random(in: 1...Int32.max)
    var pageNo: UInt32 = 0
    var granulePos: UInt64 = 0

    // Get encoder pre-skip (lookahead)
    let preSkip: UInt16 = 312  // Default Opus pre-skip for 48kHz

    // Write OpusHead page (BOS - Beginning of Stream)
    let opusHead = createOpusHeadPacket(channels: channels, sampleRate: sampleRate, preSkip: preSkip)
    try writeOggPage(
      &oggOutput,
      packet: opusHead,
      serialNo: serialNo,
      pageNo: &pageNo,
      granulePos: 0,
      headerType: 0x02  // BOS flag
    )

    // Write OpusTags page
    let opusTags = createOpusTagsPacket()
    try writeOggPage(
      &oggOutput,
      packet: opusTags,
      serialNo: serialNo,
      pageNo: &pageNo,
      granulePos: 0,
      headerType: 0x00
    )

    // Write audio pages
    for (index, packet) in opusPackets.enumerated() {
      granulePos += UInt64(Self.frameSize)
      let isLast = index == opusPackets.count - 1
      let headerType: UInt8 = isLast ? 0x04 : 0x00  // EOS flag on last page

      try writeOggPage(
        &oggOutput,
        packet: packet,
        serialNo: serialNo,
        pageNo: &pageNo,
        granulePos: granulePos,
        headerType: headerType
      )
    }

    return oggOutput
  }

  /// Create OpusHead header packet
  private func createOpusHeadPacket(channels: Int, sampleRate: Int, preSkip: UInt16) -> Data {
    var data = Data()

    // Magic signature "OpusHead"
    data.append(contentsOf: "OpusHead".utf8)

    // Version (1)
    data.append(1)

    // Channel count
    data.append(UInt8(channels))

    // Pre-skip (little-endian)
    data.append(UInt8(preSkip & 0xFF))
    data.append(UInt8((preSkip >> 8) & 0xFF))

    // Input sample rate (little-endian, for informational purposes)
    let rate = UInt32(sampleRate)
    data.append(UInt8(rate & 0xFF))
    data.append(UInt8((rate >> 8) & 0xFF))
    data.append(UInt8((rate >> 16) & 0xFF))
    data.append(UInt8((rate >> 24) & 0xFF))

    // Output gain (0)
    data.append(0)
    data.append(0)

    // Channel mapping family (0 = mono/stereo)
    data.append(0)

    return data
  }

  /// Create OpusTags metadata packet
  private func createOpusTagsPacket() -> Data {
    var data = Data()

    // Magic signature "OpusTags"
    data.append(contentsOf: "OpusTags".utf8)

    // Vendor string
    let vendor = "expo-opus"
    let vendorLength = UInt32(vendor.count)
    data.append(UInt8(vendorLength & 0xFF))
    data.append(UInt8((vendorLength >> 8) & 0xFF))
    data.append(UInt8((vendorLength >> 16) & 0xFF))
    data.append(UInt8((vendorLength >> 24) & 0xFF))
    data.append(contentsOf: vendor.utf8)

    // Comment list length (0 comments)
    data.append(contentsOf: [0, 0, 0, 0])

    return data
  }

  /// Write an OGG page
  private func writeOggPage(
    _ output: inout Data,
    packet: Data,
    serialNo: Int32,
    pageNo: inout UInt32,
    granulePos: UInt64,
    headerType: UInt8
  ) throws {
    var page = Data()

    // Capture pattern "OggS"
    page.append(contentsOf: [0x4F, 0x67, 0x67, 0x53])

    // Stream structure version (0)
    page.append(0)

    // Header type flag
    page.append(headerType)

    // Granule position (little-endian)
    for i in 0..<8 {
      page.append(UInt8((granulePos >> (i * 8)) & 0xFF))
    }

    // Serial number (little-endian)
    let serial = UInt32(bitPattern: serialNo)
    for i in 0..<4 {
      page.append(UInt8((serial >> (i * 8)) & 0xFF))
    }

    // Page sequence number (little-endian)
    for i in 0..<4 {
      page.append(UInt8((pageNo >> (i * 8)) & 0xFF))
    }

    // CRC placeholder (will be filled later)
    let crcOffset = page.count
    page.append(contentsOf: [0, 0, 0, 0])

    // Segment table
    let segmentCount = (packet.count + 254) / 255
    page.append(UInt8(segmentCount))

    var remaining = packet.count
    for _ in 0..<segmentCount {
      let segmentSize = min(remaining, 255)
      page.append(UInt8(segmentSize))
      remaining -= segmentSize
    }

    // Packet data
    page.append(packet)

    // Calculate and insert CRC
    let crc = calculateOggCRC(data: page)
    page[crcOffset] = UInt8(crc & 0xFF)
    page[crcOffset + 1] = UInt8((crc >> 8) & 0xFF)
    page[crcOffset + 2] = UInt8((crc >> 16) & 0xFF)
    page[crcOffset + 3] = UInt8((crc >> 24) & 0xFF)

    output.append(page)
    pageNo += 1
  }

  /// Calculate OGG CRC32
  private func calculateOggCRC(data: Data) -> UInt32 {
    // OGG uses a specific CRC32 polynomial
    var crc: UInt32 = 0

    for byte in data {
      crc = (crc << 8) ^ Self.oggCrcTable[Int((crc >> 24) ^ UInt32(byte))]
    }

    return crc
  }

  /// OGG CRC32 lookup table
  private static let oggCrcTable: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
      var r = UInt32(i) << 24
      for _ in 0..<8 {
        if (r & 0x80000000) != 0 {
          r = (r << 1) ^ 0x04C11DB7
        } else {
          r = r << 1
        }
      }
      table[i] = r
    }
    return table
  }()
}
