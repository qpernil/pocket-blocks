import Foundation
import AVFoundation

@main struct AudioTests {
    @MainActor static func main() throws {
        var checks = 0
        var variants = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }

        // Decode and inspect the actual generated files without opening an audio output device.
        func validate(_ data: Data, duration: Double, label: String) throws -> [Double] {
            let bytes = [UInt8](data)
            check(bytes.count >= 44, "\(label): WAV header exists")
            func text(_ offset: Int, _ count: Int) -> String {
                String(decoding: bytes[offset..<(offset + count)], as: UTF8.self)
            }
            func uint32(_ offset: Int) -> UInt32 {
                (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
            }
            check(text(0, 4) == "RIFF" && text(8, 4) == "WAVE", "\(label): valid WAV container")
            check(text(12, 4) == "fmt " && text(36, 4) == "data", "\(label): format and sample chunks exist")
            check(Int(uint32(4)) + 8 == bytes.count, "\(label): correct container length")
            let sampleBytes = Int(uint32(40))
            check(sampleBytes > 0 && sampleBytes % 2 == 0 && sampleBytes + 44 == bytes.count,
                  "\(label): complete 16-bit sample data")
            let player = try AVAudioPlayer(data: data)
            check(player.format.channelCount == 1 && player.format.sampleRate == 44_100,
                  "\(label): decoder accepts 44.1 kHz mono audio")
            check(abs(player.duration - duration) < 0.001, "\(label): decoder duration matches gameplay timing")
            check(!player.isPlaying, "\(label): validation does not play audio")
            var samples: [Double] = []
            for offset in stride(from: 44, to: bytes.count, by: 2) {
                let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                samples.append(Double(Int16(bitPattern: bits)) / 32_768)
            }
            check(abs(Double(samples.count) / 44_100 - duration) < 0.0001,
                  "\(label): PCM duration matches gameplay timing")
            check(samples.allSatisfy { abs($0) < 0.98 }, "\(label): no clipped samples")
            let energy = samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)
            check(energy > 0.000001, "\(label): sound is not silent")
            check(abs(samples.first!) < 0.03 && abs(samples.last!) < 0.03,
                  "\(label): sound starts and ends near zero")
            variants += 1
            return samples
        }

        for effect in GameSounds.Effect.allCases {
            _ = try validate(GameSounds.effectData(effect), duration: effect.duration,
                             label: String(describing: effect))
        }
        for hundredths in 11...28 {
            let duration = Double(hundredths) / 100
            let samples = try validate(GameSounds.fallData(duration: duration), duration: duration,
                                       label: "fall \(hundredths) hundredths")
            var frequencies: [Double] = []
            for part in 0..<4 {
                let start = part * samples.count / 4
                let end = (part + 1) * samples.count / 4
                let window = Array(samples[start..<end])
                let crossings = zip(window, window.dropFirst()).filter { $0.0 <= 0 && $0.1 > 0 }.count
                frequencies.append(Double(crossings) * 44_100 / Double(window.count))
            }
            check(zip(frequencies, frequencies.dropFirst()).allSatisfy { $0.0 > $0.1 },
                  "Fall whistle descends in pitch throughout its duration")
        }
        print("Passed \(checks) audio checks across \(variants) generated sounds; no playback required")
    }
}
