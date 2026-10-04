import Foundation

/// Portable 16-bit mono WAV encoding for bounded microphone captures. No answer
/// context, recognition rewriting or network operation belongs in this utility.
public enum VoiceWAV {
    /// Validate provider output before handing it to a decoder/player. RIFF chunk
    /// sizes and sample metadata are untrusted; never allocate from those sizes.
    static func validateOutput(_ data: Data) throws {
        guard (44...25_000_000).contains(data.count) else { throw SpeechServiceError.malformed }
        let base = data.startIndex
        func u16(_ offset: Int) -> Int { Int(data[base + offset]) | Int(data[base + offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int {
            var value = 0
            for byte in 0..<4 { value |= Int(data[base + offset + byte]) << (byte * 8) }
            return value
        }
        func tag(_ offset: Int, _ value: String) -> Bool { data[(base + offset)..<(base + offset + 4)].elementsEqual(value.utf8) }
        guard tag(0, "RIFF"), tag(8, "WAVE"), u32(4) == data.count - 8 else { throw SpeechServiceError.malformed }
        var offset = 12
        var chunks = 0
        var sampleRate: Int?, alignment: Int?, sampleBytes: Int?
        while offset < data.count {
            chunks += 1
            guard chunks <= 1024 else { throw SpeechServiceError.malformed }
            guard data.count - offset >= 8 else { throw SpeechServiceError.malformed }
            let size = u32(offset + 4), start = offset + 8
            guard size <= data.count - start else { throw SpeechServiceError.malformed }
            if tag(offset, "fmt ") {
                guard sampleRate == nil, size >= 16 else { throw SpeechServiceError.malformed }
                let format = u16(start), channels = u16(start + 2), rate = u32(start + 4)
                let byteRate = u32(start + 8), block = u16(start + 12), bits = u16(start + 14)
                guard (1...2).contains(channels), (8_000...96_000).contains(rate),
                      (format == 1 && [16, 24, 32].contains(bits)) || (format == 3 && bits == 32),
                      block == channels * bits / 8, byteRate == rate * block else { throw SpeechServiceError.malformed }
                sampleRate = rate; alignment = block
            } else if tag(offset, "data") {
                guard sampleBytes == nil, size > 0 else { throw SpeechServiceError.malformed }
                sampleBytes = size
            }
            // Odd RIFF chunks include one padding byte, which must exist too.
            let padded = size + size % 2
            guard padded <= data.count - start else { throw SpeechServiceError.malformed }
            offset = start + padded
        }
        guard let rate = sampleRate, let block = alignment, let bytes = sampleBytes,
              bytes % block == 0, bytes / block <= rate * 300 else { throw SpeechServiceError.malformed }
    }

    public static func encode(_ samples: [Float], sampleRate: Int = 16_000) throws -> Data {
        guard (8_000...48_000).contains(sampleRate), !samples.isEmpty,
              samples.count <= sampleRate * 120, samples.allSatisfy(\.isFinite) else { throw SpeechServiceError.invalidInput }
        let bytes = UInt32(samples.count * 2)
        var data = Data(); data.reserveCapacity(Int(bytes) + 44)
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func u32(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> shift) & 255)) } }
        text("RIFF"); u32(36 + bytes); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        text("data"); u32(bytes)
        for sample in samples {
            let value = max(-1, min(1, sample))
            let scaled = Int16((value * (value < 0 ? 32768 : 32767)).rounded())
            u16(UInt16(bitPattern: scaled))
        }
        return data
    }
}
