import AVFoundation

/// Renders the app's sounds into short PCM buffers once, at first use.
///
/// Sound design (water, warmth, a human touch), following common interactive
/// sound practice:
///  1. One family: every cue lives in D major pentatonic around D3 to D5, with the
///     same timbre (rounded sines, a soft sub, gentle low pass), so the app has
///     one voice instead of a pile of effects.
///  2. Form follows the gesture: taps are single droplets, wearing is a rising
///     pour, taking off falls, a drag is a slosh, a release wobbles like jelly.
///  3. Frequency sets loudness: the more often a cue plays (taps, ticks), the
///     shorter and quieter it is; rare moments (a match, saved) are richer.
///  4. No sharp edges: 8 to 25 ms attacks, long rounded decays, everything low
///     passed under about 2 kHz, nothing piercing.
///  5. Warmth on small speakers: iPhone speakers can't play real bass, so low
///     notes carry 2nd to 4th harmonics (the ear hears the missing fundamental)
///     and a sub an octave down for headphones.
///  6. Water: bubble style droplets glide UP in pitch as they decay (Minnaert
///     resonance), with a slow tremolo or wobble for liquid movement.
///  7. Sound and touch together: each cue fires with its haptic (Feedback.swift),
///     and the haptics are kept round and low in sharpness to match.
/// No audio files, so nothing to license.
enum ToneSynth {
    struct Note {
        var start: Double = 0
        var freq: Double
        /// Glide from `from` to `freq` with this time constant (seconds).
        var from: Double? = nil
        var glide: Double = 0.04
        var attack: Double = 0.014
        var decay: Double = 0.12
        var amp: Double = 1
        /// (multiple of freq, level)
        var partials: [(Double, Double)] = ToneSynth.water
        /// Level of a sine one octave below (felt on headphones, implied on speakers).
        var sub: Double = 0.3
        /// Wobble (rate Hz, depth as a fraction of freq, decay seconds): jelly and water.
        var vibrato: (rate: Double, depth: Double, decay: Double)? = nil
        /// Slow amplitude ripple (rate Hz, depth 0...1): liquid movement.
        var tremolo: (rate: Double, depth: Double)? = nil
        /// Level of soft, dark noise under the note (a watery wash), shaped by
        /// the same envelope and filtered low before the master low pass.
        var noise: Double = 0
        var noiseCutoff: Double = 420
    }

    // D major pentatonic, low and warm
    static let D2 = 73.42, A2 = 110.0
    static let D3 = 146.83, E3 = 164.81, Fs3 = 185.0, A3 = 220.0, B3 = 246.94
    static let D4 = 293.66, E4 = 329.63, Fs4 = 369.99, A4 = 440.0, B4 = 493.88, D5 = 587.33

    static let water: [(Double, Double)] = [(1, 1), (2, 0.16), (3, 0.04)]
    /// Low notes: strong low harmonics so phone speakers still say "bass".
    static let warm: [(Double, Double)] = [(1, 1), (2, 0.55), (3, 0.28), (4, 0.1)]
    static let glass: [(Double, Double)] = [(1, 1), (2, 0.2), (3.01, 0.05)]

    static func render(_ id: SoundID, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (notes, length, peak, cutoff) = recipe(id)
        return render(notes, length: length, peak: peak, cutoff: cutoff, format: format)
    }

    /// A water droplet: rises in pitch as it rings out.
    static func drop(_ start: Double, _ f: Double, amp: Double = 1, decay: Double = 0.1) -> Note {
        Note(start: start, freq: f, from: f * 0.62, glide: 0.035, attack: 0.008, decay: decay, amp: amp, sub: 0.2)
    }

    // MARK: Recipes (notes, length s, peak level, low pass cutoff Hz)

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func recipe(_ id: SoundID) -> ([Note], Double, Double, Double) {
        switch id {
        case .tap:
            return ([drop(0, D5, decay: 0.06)], 0.22, 0.14, 2000)
        case .press:
            return ([
                drop(0, D4, decay: 0.09),
                Note(freq: D3, attack: 0.01, decay: 0.06, amp: 0.55, partials: warm, sub: 0.5),
            ], 0.3, 0.22, 1500)
        case .tab:
            return ([drop(0, Fs4, decay: 0.07)], 0.24, 0.15, 1800)
        case .toggleOn:
            return ([drop(0, D4, amp: 0.8, decay: 0.07), drop(0.07, A4, decay: 0.1)], 0.36, 0.18, 1800)
        case .toggleOff:
            return ([drop(0, A4, amp: 0.8, decay: 0.07), drop(0.07, D4, decay: 0.1)], 0.36, 0.17, 1800)
        case .wear:
            // A pour: droplets climbing over a warm swell
            return ([
                Note(freq: D3, attack: 0.08, decay: 0.3, amp: 0.7, partials: warm, sub: 0.5, tremolo: (5.5, 0.25)),
                drop(0.03, D4, amp: 0.8), drop(0.11, Fs4, amp: 0.8), drop(0.19, A4, decay: 0.22),
            ], 0.85, 0.26, 1900)
        case .takeOff:
            return ([
                Note(freq: D3, from: Fs3, glide: 0.12, attack: 0.05, decay: 0.25, amp: 0.7, partials: warm, sub: 0.5),
                drop(0, A4, amp: 0.7), drop(0.08, Fs4, amp: 0.7), drop(0.16, D4, decay: 0.18),
            ], 0.75, 0.24, 1600)
        case .poke:
            // A squishy bloop
            return ([Note(freq: B3, from: E3, glide: 0.035, attack: 0.012, decay: 0.1, partials: warm, sub: 0.4,
                          vibrato: (rate: 7, depth: 0.04, decay: 0.08))], 0.3, 0.22, 1300)
        case .pop:
            return ([drop(0, A4, decay: 0.08), drop(0.06, D5, amp: 0.45, decay: 0.07)], 0.34, 0.2, 2000)
        case .land:
            return ([Note(freq: D3, from: Fs3, glide: 0.03, attack: 0.01, decay: 0.08, partials: warm, sub: 0.5)],
                    0.26, 0.2, 900)
        case .boingSmall:
            return ([Note(freq: B3, from: E4, glide: 0.06, attack: 0.012, decay: 0.24, partials: warm, sub: 0.35,
                          vibrato: (rate: 6, depth: 0.07, decay: 0.26))], 0.7, 0.24, 1300)
        case .boingBig:
            return ([Note(freq: Fs3, from: D4, glide: 0.08, attack: 0.014, decay: 0.38, partials: warm, sub: 0.45,
                          vibrato: (rate: 4.8, depth: 0.1, decay: 0.4))], 1.1, 0.28, 1150)
        case .chime:
            // A match appears: a rising, bubbly chord over a soft pad
            return ([
                Note(freq: D3, attack: 0.12, decay: 0.45, amp: 0.55, partials: warm, sub: 0.4, tremolo: (4.5, 0.3)),
                drop(0.0, D4, amp: 0.7, decay: 0.3), drop(0.08, Fs4, amp: 0.7, decay: 0.3),
                drop(0.16, A4, amp: 0.75, decay: 0.35), drop(0.26, D5, amp: 0.5, decay: 0.45),
            ], 1.5, 0.26, 2100)
        case .tick(let step):
            // A muffled heartbeat under water: lub dub, faster and a bit higher as they come closer
            let x = Double(step) / Double(SoundID.tickSteps - 1)
            let f = 98 * pow(2, x * 0.5) // about G2 to D3
            return ([
                Note(freq: f, from: f * 1.25, glide: 0.02, attack: 0.012, decay: 0.09, partials: warm, sub: 0.6),
                Note(start: 0.17, freq: f * 0.9, from: f * 1.1, glide: 0.02, attack: 0.012, decay: 0.08,
                     amp: 0.6, partials: warm, sub: 0.6),
            ], 0.5, 0.22 + 0.08 * x, 700 + 400 * x)
        case .met:
            // We finally met: a stone dropping into a lake. A low, soft thump
            // that sinks, then a dark wash that spreads and settles, with a few
            // slow ripples drifting outward. Relief, not a fanfare.
            return ([
                // The stone: a round low hit, falling a little as it lands
                Note(freq: D2, from: A2, glide: 0.06, attack: 0.014, decay: 0.28, partials: warm, sub: 0.35),
                // Its body on small speakers
                Note(freq: D3, from: Fs3, glide: 0.07, attack: 0.02, decay: 0.32, amp: 0.45, partials: warm, sub: 0.5),
                // The water closing over it: a slow swell of low noise and a soft fifth
                Note(start: 0.04, freq: A2, attack: 0.3, decay: 0.85, amp: 0.4,
                     partials: [(1, 0.35), (1.5, 0.18), (2, 0.1)], sub: 0.2, tremolo: (3.2, 0.35),
                     noise: 1.4, noiseCutoff: 380),
                // Ripples spreading out: each one later, lower and quieter
                drop(0.2, A3, amp: 0.3, decay: 0.22),
                drop(0.42, Fs3, amp: 0.22, decay: 0.28),
                drop(0.7, D3, amp: 0.15, decay: 0.36),
            ], 2.1, 0.3, 950)
        case .talk:
            return ([
                Note(freq: D3, attack: 0.06, decay: 0.3, amp: 0.6, partials: warm, sub: 0.4, tremolo: (5, 0.25)),
                drop(0.02, D4, decay: 0.16), drop(0.12, Fs4, decay: 0.22),
            ], 0.8, 0.24, 1700)
        case .celebrate:
            // Saved: a warm pour that settles
            var notes: [Note] = [
                Note(freq: D3, attack: 0.15, decay: 0.6, amp: 0.6, partials: warm, sub: 0.45, tremolo: (4, 0.3)),
            ]
            for (i, f) in [D4, Fs4, A4, B4, D5].enumerated() {
                notes.append(drop(Double(i) * 0.08, f, amp: i == 4 ? 0.7 : 0.75, decay: i == 4 ? 0.5 : 0.18))
            }
            return (notes, 1.6, 0.27, 2100)
        case .error:
            return ([
                Note(freq: A3, attack: 0.015, decay: 0.12, partials: warm, sub: 0.4),
                Note(start: 0.14, freq: Fs3, attack: 0.015, decay: 0.16, partials: warm, sub: 0.4),
            ], 0.6, 0.22, 1100)
        }
    }

    // MARK: Rendering

    static func render(_ notes: [Note], length: Double, peak: Double, cutoff: Double,
                       format: AVAudioFormat) -> AVAudioPCMBuffer? {
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
            // Noise: a fixed seed so the sound is the same every launch
            var seed: UInt32 = 0x9E37_79B9 &+ UInt32(first)
            var dark = 0.0
            let kNoise = 1 - exp(-2 * .pi * note.noiseCutoff / sr)
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
                // Rounded attack (raised cosine), exponential decay
                var a = t < note.attack
                    ? 0.5 - 0.5 * cos(.pi * t / note.attack)
                    : exp(-(t - note.attack) / note.decay)
                if a < 0.0004 && t > note.attack { break }
                if let tr = note.tremolo { a *= 1 - tr.depth * (0.5 + 0.5 * sin(2 * .pi * tr.rate * t)) }
                var s = sin(phase * 0.5) * note.sub
                for (mult, level) in note.partials { s += sin(phase * mult) * level }
                if note.noise > 0 {
                    seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                    let white = Double(seed) / Double(UInt32.max) * 2 - 1
                    dark += kNoise * (white - dark)
                    s += dark * note.noise * 3 // the low pass takes most of its level
                }
                out[i] += Float(s * a * note.amp)
            }
        }

        // Two pole low pass (two cascaded one poles): rounds every edge
        let k = Float(1 - exp(-2 * .pi * cutoff / sr))
        var y1: Float = 0, y2: Float = 0
        for i in 0..<n {
            y1 += k * (out[i] - y1)
            y2 += k * (y1 - y2)
            out[i] = y2
        }

        // Normalize to the recipe's level and fade the tail to avoid clicks
        var maxValue: Float = 0
        for i in 0..<n { maxValue = max(maxValue, abs(out[i])) }
        let gain = maxValue > 0 ? Float(peak) / maxValue : 0
        let fade = min(n, Int(0.03 * sr))
        for i in 0..<n {
            var g = gain
            if i >= n - fade { g *= Float(n - i) / Float(fade) }
            out[i] *= g
        }
        return buffer
    }
}
