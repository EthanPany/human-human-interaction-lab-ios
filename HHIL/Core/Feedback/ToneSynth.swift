import AVFoundation

/// Renders the app's sounds into short PCM buffers once, at first use.
/// One timbre for everything: sines with a touch of second harmonic, quick soft
/// attacks and exponential decays, pitch glides for the bubbly ones and bell
/// partials for chimes. No audio files, so nothing to license.
enum ToneSynth {
    struct Note {
        var start: Double = 0
        var freq: Double
        /// Glide from `from` to `freq` with this time constant (seconds).
        var from: Double? = nil
        var glide: Double = 0.03
        var amp: Double = 1
        var attack: Double = 0.004
        var decay: Double = 0.08
        /// (multiple of freq, level)
        var partials: [(Double, Double)] = [(1, 1), (2, 0.12)]
        /// Wobble (rate Hz, depth as a fraction of freq, decay seconds): the jelly boing.
        var vibrato: (rate: Double, depth: Double, decay: Double)? = nil
    }

    static let soft: [(Double, Double)] = [(1, 1), (2, 0.12)]
    static let bell: [(Double, Double)] = [(1, 1), (2, 0.28), (3.01, 0.08)]
    static let round: [(Double, Double)] = [(1, 1), (2, 0.22), (3, 0.06)]

    static func render(_ id: SoundID, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (notes, length, peak) = recipe(id)
        return render(notes, length: length, peak: peak, format: format)
    }

    // MARK: Recipes

    // swiftlint:disable:next cyclomatic_complexity
    static func recipe(_ id: SoundID) -> ([Note], Double, Double) {
        switch id {
        case .tap:
            return ([Note(freq: 1250, from: 1400, glide: 0.01, decay: 0.018)], 0.06, 0.22)
        case .press:
            return ([Note(freq: 440, from: 540, glide: 0.02, decay: 0.03, partials: round)], 0.09, 0.32)
        case .tab:
            return ([Note(freq: 940, decay: 0.022)], 0.07, 0.2)
        case .toggleOn:
            return ([Note(freq: 660, decay: 0.03), Note(start: 0.05, freq: 990, decay: 0.05)], 0.16, 0.26)
        case .toggleOff:
            return ([Note(freq: 990, decay: 0.03), Note(start: 0.05, freq: 660, decay: 0.05)], 0.16, 0.24)
        case .wear:
            return ([
                Note(freq: 784, from: 392, glide: 0.07, attack: 0.01, decay: 0.14),
                Note(start: 0.12, freq: 1568, amp: 0.35, decay: 0.12, partials: bell),
            ], 0.42, 0.34)
        case .takeOff:
            return ([Note(freq: 392, from: 784, glide: 0.07, attack: 0.008, decay: 0.12)], 0.34, 0.3)
        case .poke:
            return ([Note(freq: 420, from: 250, glide: 0.015, decay: 0.03, partials: round)], 0.08, 0.3)
        case .pop:
            return ([
                Note(freq: 1150, from: 380, glide: 0.02, attack: 0.002, decay: 0.035),
                Note(start: 0.055, freq: 1900, from: 1400, glide: 0.012, amp: 0.4, decay: 0.025),
            ], 0.13, 0.34)
        case .land:
            return ([Note(freq: 260, from: 330, glide: 0.02, decay: 0.03, partials: round)], 0.07, 0.2)
        case .boingSmall:
            return ([Note(freq: 420, from: 640, glide: 0.04, attack: 0.003, decay: 0.12,
                          vibrato: (rate: 12, depth: 0.09, decay: 0.12))], 0.36, 0.3)
        case .boingBig:
            return ([Note(freq: 300, from: 560, glide: 0.06, attack: 0.003, decay: 0.2,
                          vibrato: (rate: 9, depth: 0.14, decay: 0.2))], 0.6, 0.36)
        case .chime:
            return ([
                Note(freq: 659.3, decay: 0.22, partials: bell),
                Note(start: 0.11, freq: 987.8, decay: 0.38, partials: bell),
            ], 0.95, 0.32)
        case .tick(let step):
            // A soft "lub dub": main ping, then a lower, quieter echo.
            let f = 440 * pow(2, Double(step) / Double(SoundID.tickSteps - 1) * 0.75) // 440 to 740 Hz
            return ([
                Note(freq: f, attack: 0.006, decay: 0.07, partials: bell),
                Note(start: 0.13, freq: f * 0.84, amp: 0.55, attack: 0.006, decay: 0.06, partials: bell),
            ], 0.45, 0.24)
        case .talk:
            return ([
                Note(freq: 392, from: 360, glide: 0.02, decay: 0.08, partials: round),
                Note(start: 0.1, freq: 523.3, from: 480, glide: 0.02, decay: 0.12, partials: round),
            ], 0.5, 0.3)
        case .celebrate:
            let pitches: [Double] = [523.3, 659.3, 784, 1046.5]
            var notes: [Note] = []
            for (i, f) in pitches.enumerated() {
                let last = i == pitches.count - 1
                notes.append(Note(start: Double(i) * 0.075, freq: f, amp: last ? 1 : 0.8,
                                  decay: last ? 0.42 : 0.12, partials: bell))
            }
            notes.append(Note(start: 0.3, freq: 1568, amp: 0.25, decay: 0.3, partials: bell))
            return (notes, 1.25, 0.32)
        case .error:
            return ([
                Note(freq: 440, decay: 0.07, partials: round),
                Note(start: 0.12, freq: 349.2, decay: 0.1, partials: round),
            ], 0.4, 0.28)
        }
    }

    // MARK: Rendering

    static func render(_ notes: [Note], length: Double, peak: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(length * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let n = Int(frames)
        for i in 0..<n { out[i] = 0 }

        for note in notes {
            let first = Int(note.start * sr)
            guard first < n else { continue }
            var phase = 0.0
            for i in first..<n {
                let t = Double(i - first) / sr
                // Exponential glide in pitch (sounds even across octaves)
                var f = note.freq
                if let from = note.from {
                    f = note.freq * pow(from / note.freq, exp(-t / note.glide))
                }
                if let v = note.vibrato {
                    f *= 1 + v.depth * exp(-t / v.decay) * sin(2 * .pi * v.rate * t)
                }
                phase += 2 * .pi * f / sr
                // Smooth attack, exponential decay
                let a = t < note.attack ? sin(.pi / 2 * t / note.attack) : exp(-(t - note.attack) / note.decay)
                if a < 0.0005 && t > note.attack { break }
                var s = 0.0
                for (mult, level) in note.partials { s += sin(phase * mult) * level }
                out[i] += Float(s * a * note.amp)
            }
        }

        // Normalize to the recipe's level and fade the tail to avoid clicks
        var maxValue: Float = 0
        for i in 0..<n { maxValue = max(maxValue, abs(out[i])) }
        let gain = maxValue > 0 ? Float(peak) / maxValue : 0
        let fade = min(n, Int(0.008 * sr))
        for i in 0..<n {
            var g = gain
            if i >= n - fade { g *= Float(n - i) / Float(fade) }
            out[i] *= g
        }
        return buffer
    }
}
