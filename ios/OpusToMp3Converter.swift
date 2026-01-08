import Foundation
import opus
import lame

/// OGG Opus to MP3 Converter
///
/// This class handles the conversion of OGG Opus audio files to MP3 format.
/// It uses libopus for Opus decoding and LAME for MP3 encoding.
internal class OpusToMp3Converter {

  // MARK: - Constants

  private static let maxFrameSize = 5760 // Maximum frame size for 120ms at 48kHz
  private static let maxPacketSize = 4000 // Maximum Opus packet size
  private static let mp3BufferSize = 8640 // LAME recommended buffer size

  // MARK: - Public Methods

  /// Convert OGG Opus audio data to MP3
  /// - Parameters:
  ///   - inputData: Raw OGG Opus audio data
  ///   - bitrate: Target MP3 bitrate in kbps (64-320)
  ///   - sampleRate: Optional target sample rate
  /// - Returns: Converted audio data with MP3 content
  func convert(inputData: Data, bitrate: Int, sampleRate: Int?) async throws -> ConvertedAudio {
    // Step 1: Parse OGG container and extract Opus packets
    let oggData = try parseOggContainer(data: inputData)

    // Step 2: Decode Opus to PCM
    let pcmData = try decodeOpusToPCM(oggData: oggData)

    // Step 3: Encode PCM to MP3
    let targetSampleRate = sampleRate ?? pcmData.sampleRate
    let mp3Data = try encodePCMToMP3(
      pcmData: pcmData,
      bitrate: bitrate,
      targetSampleRate: targetSampleRate
    )

    return ConvertedAudio(data: mp3Data, durationMs: pcmData.durationMs)
  }

  // MARK: - OGG Parsing

  /// OGG page structure for parsing
  private struct OggPage {
    let granulePosition: UInt64
    let serialNumber: UInt32
    let pageNumber: UInt32
    let segments: [Data]
  }

  /// OGG stream data
  private struct OggData {
    let packets: [Data]
    let sampleRate: Int
    let channels: Int
  }

  /// Parse OGG container to extract Opus packets
  private func parseOggContainer(data: Data) throws -> OggData {
    var offset = 0
    var packets: [Data] = []
    var currentPacket = Data()
    var sampleRate = 48000 // Default Opus sample rate
    var channels = 2 // Default stereo

    while offset < data.count {
      let pageHeader = try parseOggPageHeader(data: data, offset: offset)
      let segmentSizes = try readSegmentTable(
        data: data,
        offset: offset + 27,
        count: pageHeader.segmentCount
      )

      let processResult = try processOggSegments(
        data: data,
        segmentSizes: segmentSizes,
        dataOffset: offset + 27 + pageHeader.segmentCount,
        currentPacket: currentPacket,
        packets: packets,
        sampleRate: sampleRate,
        channels: channels
      )

      packets = processResult.packets
      currentPacket = processResult.currentPacket
      sampleRate = processResult.sampleRate
      channels = processResult.channels
      offset = processResult.nextOffset
    }

    guard !packets.isEmpty else {
      throw DecodingFailedException("No audio packets found in OGG stream")
    }

    return OggData(packets: packets, sampleRate: sampleRate, channels: channels)
  }

  /// Parse OGG page header
  private func parseOggPageHeader(data: Data, offset: Int) throws -> (segmentCount: Int, headerTypeFlag: UInt8) {
    guard offset + 27 <= data.count else {
      throw DecodingFailedException("Incomplete OGG page header")
    }

    let capturePattern = data[offset..<(offset + 4)]
    guard capturePattern.elementsEqual([0x4F, 0x67, 0x67, 0x53]) else {
      throw DecodingFailedException("Invalid OGG page header")
    }

    let headerTypeFlag = data[offset + 5]
    let segmentCount = Int(data[offset + 26])

    guard offset + 27 + segmentCount <= data.count else {
      throw DecodingFailedException("Incomplete OGG page")
    }

    return (segmentCount, headerTypeFlag)
  }

  /// Read segment table from OGG page
  private func readSegmentTable(data: Data, offset: Int, count: Int) throws -> [Int] {
    var segmentSizes: [Int] = []
    for i in 0..<count {
      segmentSizes.append(Int(data[offset + i]))
    }
    return segmentSizes
  }

  /// Process OGG segments and extract packets
  private func processOggSegments(
    data: Data,
    segmentSizes: [Int],
    dataOffset: Int,
    currentPacket: Data,
    packets: [Data],
    sampleRate: Int,
    channels: Int
  ) throws -> (packets: [Data], currentPacket: Data, sampleRate: Int, channels: Int, nextOffset: Int) {
    var mutableCurrentPacket = currentPacket
    var mutablePackets = packets
    var mutableSampleRate = sampleRate
    var mutableChannels = channels
    var offset = dataOffset

    for size in segmentSizes {
      guard offset + size <= data.count else {
        throw DecodingFailedException("Segment data overflow")
      }

      mutableCurrentPacket.append(data[offset..<(offset + size)])
      offset += size

      // Packet complete if segment size < 255
      if size < 255 && !mutableCurrentPacket.isEmpty {
        let packetResult = processCompletePacket(
          packet: mutableCurrentPacket,
          channels: mutableChannels,
          sampleRate: mutableSampleRate
        )

        if let audioPacket = packetResult.audioPacket {
          mutablePackets.append(audioPacket)
        }
        mutableChannels = packetResult.channels
        mutableSampleRate = packetResult.sampleRate
        mutableCurrentPacket = Data()
      }
    }

    return (mutablePackets, mutableCurrentPacket, mutableSampleRate, mutableChannels, offset)
  }

  /// Process a complete OGG packet
  private func processCompletePacket(
    packet: Data,
    channels: Int,
    sampleRate: Int
  ) -> (audioPacket: Data?, channels: Int, sampleRate: Int) {
    guard packet.count >= 8 else {
      return (packet.count > 0 ? packet : nil, channels, sampleRate)
    }

    let signature = String(data: packet[0..<8], encoding: .ascii)

    if signature == "OpusHead" && packet.count >= 12 {
      return parseOpusHeader(packet: packet)
    } else if signature?.starts(with: "OpusTags") == true {
      return (nil, channels, sampleRate)
    } else {
      return (packet, channels, sampleRate)
    }
  }

  /// Parse Opus header packet
  private func parseOpusHeader(packet: Data) -> (audioPacket: Data?, channels: Int, sampleRate: Int) {
    let channels = Int(packet[9])
    // Opus internally always uses 48kHz regardless of the original sample rate stored in header
    let sampleRate = 48000

    return (nil, channels, sampleRate)
  }

  // MARK: - Opus Decoding (using libopus)

  /// Decode Opus packets to PCM samples
  private func decodeOpusToPCM(oggData: OggData) throws -> PCMData {
    let decoder = try createOpusDecoder(
      sampleRate: oggData.sampleRate,
      channels: oggData.channels
    )

    defer {
      opus_decoder_destroy(decoder)
    }

    let samples = try decodeAllPackets(
      decoder: decoder,
      packets: oggData.packets,
      channels: oggData.channels
    )

    // Use Int64 to prevent integer overflow for large audio files
    let durationMs = Int((Int64(samples.count) / Int64(oggData.channels)) * 1000 / Int64(oggData.sampleRate))

    return PCMData(
      samples: samples,
      sampleRate: oggData.sampleRate,
      channels: oggData.channels,
      durationMs: durationMs
    )
  }

  /// Create and initialize Opus decoder
  private func createOpusDecoder(sampleRate: Int, channels: Int) throws -> OpaquePointer {
    var error: Int32 = 0
    guard let decoder = opus_decoder_create(
      Int32(sampleRate),
      Int32(channels),
      &error
    ) else {
      throw DecodingFailedException("Failed to create Opus decoder: \(error)")
    }

    guard error == OPUS_OK else {
      throw DecodingFailedException("Opus decoder initialization failed: \(error)")
    }

    return decoder
  }

  /// Decode all Opus packets to PCM samples
  private func decodeAllPackets(
    decoder: OpaquePointer,
    packets: [Data],
    channels: Int
  ) throws -> [Int16] {
    var allSamples: [Int16] = []
    let frameBuffer = UnsafeMutablePointer<Int16>.allocate(
      capacity: Self.maxFrameSize * channels
    )
    defer { frameBuffer.deallocate() }

    for packet in packets {
      let samples = decodePacket(
        decoder: decoder,
        packet: packet,
        frameBuffer: frameBuffer,
        channels: channels
      )
      allSamples.append(contentsOf: samples)
    }

    guard !allSamples.isEmpty else {
      throw DecodingFailedException("No audio samples decoded")
    }

    return allSamples
  }

  /// Decode a single Opus packet
  private func decodePacket(
    decoder: OpaquePointer,
    packet: Data,
    frameBuffer: UnsafeMutablePointer<Int16>,
    channels: Int
  ) -> [Int16] {
    let samplesDecoded = packet.withUnsafeBytes { (packetPtr: UnsafeRawBufferPointer) -> Int32 in
      guard let baseAddress = packetPtr.baseAddress else { return 0 }
      return opus_decode(
        decoder,
        baseAddress.assumingMemoryBound(to: UInt8.self),
        Int32(packet.count),
        frameBuffer,
        Int32(Self.maxFrameSize),
        0 // No FEC
      )
    }

    guard samplesDecoded > 0 else { return [] }

    let totalSamples = Int(samplesDecoded) * channels
    return Array(UnsafeBufferPointer(start: frameBuffer, count: totalSamples))
  }

  // MARK: - MP3 Encoding (using LAME)

  /// Encode PCM samples to MP3
  private func encodePCMToMP3(pcmData: PCMData, bitrate: Int, targetSampleRate: Int) throws -> Data {
    let lame = try initializeLameEncoder()
    defer { lame_close(lame) }

    try configureLameEncoder(
      lame: lame,
      pcmData: pcmData,
      bitrate: bitrate,
      targetSampleRate: targetSampleRate
    )

    let mp3BufferSize = Int(1.25 * Double(pcmData.samples.count) + 7200)
    var mp3Buffer = Data(count: mp3BufferSize)

    let mp3Size = try performLameEncoding(
      lame: lame,
      pcmData: pcmData,
      mp3Buffer: &mp3Buffer,
      mp3BufferSize: mp3BufferSize
    )

    let flushSize = try flushLameEncoder(
      lame: lame,
      mp3Buffer: &mp3Buffer,
      offset: mp3Size,
      remainingSize: mp3BufferSize - mp3Size
    )

    let totalSize = mp3Size + flushSize
    return mp3Buffer.prefix(totalSize)
  }

  /// Initialize LAME encoder
  private func initializeLameEncoder() throws -> OpaquePointer {
    guard let lame = lame_init() else {
      throw EncodingFailedException("Failed to initialize LAME encoder")
    }
    return lame
  }

  /// Configure LAME encoder parameters
  private func configureLameEncoder(
    lame: OpaquePointer,
    pcmData: PCMData,
    bitrate: Int,
    targetSampleRate: Int
  ) throws {
    lame_set_in_samplerate(lame, Int32(pcmData.sampleRate))
    lame_set_out_samplerate(lame, Int32(targetSampleRate))
    lame_set_num_channels(lame, Int32(pcmData.channels))
    lame_set_brate(lame, Int32(bitrate))
    lame_set_quality(lame, 5) // Good quality/speed balance (0=best, 9=worst)
    lame_set_mode(lame, pcmData.channels == 1 ? MONO : JOINT_STEREO)
    lame_set_VBR(lame, vbr_off) // VBR off for consistent bitrate

    guard lame_init_params(lame) >= 0 else {
      throw EncodingFailedException("Failed to set LAME parameters")
    }
  }

  /// Perform LAME encoding
  private func performLameEncoding(
    lame: OpaquePointer,
    pcmData: PCMData,
    mp3Buffer: inout Data,
    mp3BufferSize: Int
  ) throws -> Int {
    let samplesPerChannel = pcmData.samples.count / pcmData.channels

    let mp3Size = pcmData.samples.withUnsafeBufferPointer { samplesPtr in
      mp3Buffer.withUnsafeMutableBytes { mp3Ptr in
        if pcmData.channels == 1 {
          return encodeMono(
            lame: lame,
            samplesPtr: samplesPtr,
            samplesPerChannel: samplesPerChannel,
            mp3Ptr: mp3Ptr,
            mp3BufferSize: mp3BufferSize
          )
        } else {
          return encodeStereo(
            lame: lame,
            samplesPtr: samplesPtr,
            samplesPerChannel: samplesPerChannel,
            mp3Ptr: mp3Ptr,
            mp3BufferSize: mp3BufferSize
          )
        }
      }
    }

    guard mp3Size >= 0 else {
      throw EncodingFailedException("LAME encoding failed with code: \(mp3Size)")
    }

    return mp3Size
  }

  /// Encode mono audio
  private func encodeMono(
    lame: OpaquePointer,
    samplesPtr: UnsafeBufferPointer<Int16>,
    samplesPerChannel: Int,
    mp3Ptr: UnsafeMutableRawBufferPointer,
    mp3BufferSize: Int
  ) -> Int {
    return Int(lame_encode_buffer(
      lame,
      samplesPtr.baseAddress,
      nil,
      Int32(samplesPerChannel),
      mp3Ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
      Int32(mp3BufferSize)
    ))
  }

  /// Encode stereo audio
  private func encodeStereo(
    lame: OpaquePointer,
    samplesPtr: UnsafeBufferPointer<Int16>,
    samplesPerChannel: Int,
    mp3Ptr: UnsafeMutableRawBufferPointer,
    mp3BufferSize: Int
  ) -> Int {
    return Int(lame_encode_buffer_interleaved(
      lame,
      UnsafeMutablePointer(mutating: samplesPtr.baseAddress),
      Int32(samplesPerChannel),
      mp3Ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
      Int32(mp3BufferSize)
    ))
  }

  /// Flush LAME encoder
  private func flushLameEncoder(
    lame: OpaquePointer,
    mp3Buffer: inout Data,
    offset: Int,
    remainingSize: Int
  ) throws -> Int {
    let flushSize = mp3Buffer.withUnsafeMutableBytes { mp3Ptr in
      Int(lame_encode_flush(
        lame,
        mp3Ptr.baseAddress?.advanced(by: offset).assumingMemoryBound(to: UInt8.self),
        Int32(remainingSize)
      ))
    }

    guard flushSize >= 0 else {
      throw EncodingFailedException("LAME flush failed with code: \(flushSize)")
    }

    return flushSize
  }
}
