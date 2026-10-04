import Foundation

/// Portable 16-bit mono WAV encoding for bounded microphone captures. No answer
/// context, recognition rewriting or network operation belongs in this utility.
public enum VoiceWAV {
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
