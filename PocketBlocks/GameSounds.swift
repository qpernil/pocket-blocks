import AVFoundation

/// Original synthesized effects, prepared in memory for responsive playback.
/// All mutable state and AVFoundation calls are confined to `queue`. Public commands
/// enqueue work without making the UI wait for audio-session or hardware operations.
final class GameSounds: @unchecked Sendable {
    static let shared = GameSounds()
    enum Effect: CaseIterable, Sendable {
        case rotate, land, clear, clearFour, start, gameOver
        var duration: Double {
            switch self {
            case .rotate: return 0.045
            case .land: return 0.13
            case .clear: return 0.26
            case .clearFour: return 0.42
            case .start: return 0.18
            case .gameOver: return 0.46
            }
        }
    }

    private let queue = DispatchQueue(label: "se.qpernil.PocketBlocks.audio", qos: .userInitiated)
    private var enabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    private var effects: [Effect: [AVAudioPlayer]] = [:]
    private var falls: [Int: AVAudioPlayer] = [:]
    private var activeFall: AVAudioPlayer?

    init() {
        // Preparation precedes every subsequent command on this serial queue.
        queue.async { self.prepare() }
    }

    private func prepare() {
        dispatchPrecondition(condition: .onQueue(queue))
        #if os(iOS)
        // Game effects respect the Silent switch and mix with the user's music.
        let session = AVAudioSession.sharedInstance()
        // Activation can block; use the audio queue on every supported iOS version.
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(true)
        #endif
        for effect in Effect.allCases {
            let data = Self.effectData(effect)
            effects[effect] = (0..<3).compactMap { _ in Self.player(data) }
        }
        // Every possible fall duration is prepared ahead of gameplay.
        for hundredths in 11...28 {
            falls[hundredths] = Self.player(Self.fallData(duration: Double(hundredths) / 100))
        }
    }

    private static func player(_ data: Data) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        player.volume = 0.65
        player.prepareToPlay()
        return player
    }

    func setEnabled(_ value: Bool) {
        queue.async {
            self.enabled = value
            if !value { self.stopAllOnQueue() }
        }
    }

    func play(_ effect: Effect) {
        queue.async {
            guard self.enabled, let voices = self.effects[effect],
                  let player = voices.first(where: { !$0.isPlaying }) ?? voices.first else { return }
            player.stop(); player.currentTime = 0
            player.play()
        }
    }

    func playFall(duration: Double) {
        queue.async {
            self.stopFallOnQueue()
            guard self.enabled else { return }
            let key = min(28, max(11, Int((duration * 100).rounded())))
            guard let player = self.falls[key] else { return }
            self.activeFall = player
            player.currentTime = 0
            player.play()
        }
    }

    func stopFall() {
        queue.async { self.stopFallOnQueue() }
    }

    func stopAll() {
        queue.async { self.stopAllOnQueue() }
    }

    private func stopFallOnQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
        activeFall?.stop()
        activeFall = nil
    }

    private func stopAllOnQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
        stopFallOnQueue()
        for voices in effects.values { for player in voices { player.stop() } }
    }

    // The pitch follows the same quadratic progress as the visible accelerating fall.
    // A growing pure whistle gives way to a separate impact at the actual landing.
    static func fallData(duration: Double) -> Data {
        var phase = 0.0
        return wave(duration: duration) { time, progress in
            let descent = progress * progress
            let frequency = 2200 * pow(0.19, descent)
            phase += 2 * .pi * frequency / sampleRate
            let attack = min(1, time / 0.008)
            let release = min(1, (duration - time) / 0.012)
            let swell = 0.12 + 0.37 * progress
            let whistle = sin(phase) + 0.10 * sin(phase * 2.002)
            return whistle * swell * attack * release
        }
    }

    static func effectData(_ effect: Effect) -> Data {
        var phase = 0.0
        let duration = effect.duration
        return wave(duration: duration) { time, progress in
            let attack = min(1, time / 0.004)
            let release = min(1, (duration - time) / 0.018)
            switch effect {
            case .land:
                // A low, rounded thump with a little body audible on phone speakers.
                let frequency = 170 * exp(-time * 24) + 65
                phase += 2 * .pi * frequency / sampleRate
                return (0.55 * sin(phase) + 0.17 * sin(phase * 2.0)) * exp(-time * 27) * attack * release
            case .rotate:
                phase += 2 * .pi * (950 - 260 * progress) / sampleRate
                return sin(phase) * 0.16 * pow(1 - progress, 2) * attack * release
            case .clear, .clearFour, .start:
                let notes: [Double]
                switch effect {
                case .clearFour: notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
                case .start: notes = [523.25, 659.25, 783.99]
                default: notes = [659.25, 783.99, 1046.5, 1318.5]
                }
                let step = duration / Double(notes.count)
                let index = min(notes.count - 1, Int(time / step))
                let local = time - Double(index) * step
                let noteEnvelope = min(1, local / 0.003) * min(1, (step - local) / 0.012)
                phase += 2 * .pi * notes[index] / sampleRate
                return (sin(phase) + 0.15 * sin(phase * 2)) * 0.23 * noteEnvelope * release
            case .gameOver:
                phase += 2 * .pi * (440 * pow(0.4, progress)) / sampleRate
                return (sin(phase) + 0.15 * sin(phase * 1.5)) * 0.24 * pow(1 - progress, 0.7) * attack * release
            }
        }
    }

    private static let sampleRate = 44_100.0

    /// Mono PCM WAV; kept dependency-free and deterministic for reproducible sounds.
    private static func wave(duration: Double, sample: (Double, Double) -> Double) -> Data {
        let count = Int(duration * sampleRate)
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: text.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        ascii("RIFF"); number(UInt32(36 + count * 2)); ascii("WAVE")
        ascii("fmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(sampleRate)); number(UInt32(sampleRate) * 2)
        number(UInt16(2)); number(UInt16(16))
        ascii("data"); number(UInt32(count * 2))
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let value = max(-1, min(1, sample(time, time / duration)))
            number(Int16(value * Double(Int16.max)))
        }
        return data
    }
}
