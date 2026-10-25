import AVFoundation

/// Plays the pre rendered cue buffers on a small pool of player nodes, plus one
/// live voice for the continuous squish. Uses the .ambient session, so the
/// ring/silent switch mutes it and other audio keeps playing.
@MainActor
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [SoundID: AVAudioPCMBuffer] = [:]
    let squish = SquishVoice()
    private var sessionReady = false
    private var observers: [NSObjectProtocol] = []

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        var ids: [SoundID] = [.tap, .press, .tab, .toggleOn, .toggleOff, .wear, .takeOff, .poke, .pop, .land,
                              .boingSmall, .boingBig, .chime, .met, .talk, .celebrate, .error]
        ids += (0..<SoundID.tickSteps).map { SoundID.tick($0) }
        for id in ids { buffers[id] = ToneSynth.render(id, format: format) }

        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        let voice = squish.makeNode(sampleRate: format.sampleRate)
        engine.attach(voice)
        engine.connect(voice, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.85

        // Route changes and other apps' sessions stop the engine; start again on the next sound.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.players.forEach { $0.stop() }
                self.sessionReady = false
                _ = self.ensureRunning() // a new route: come straight back up
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.sessionReady = false }
        })
    }

    /// Bring the audio hardware up ahead of the first sound (app launch and
    /// foreground), so short cues are never swallowed by a cold start.
    func warmUp() { _ = ensureRunning() }

    func play(_ id: SoundID, volume: Float = 1) {
        guard let buffer = buffers[id], ensureRunning() else { return }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    func startSquish() {
        guard ensureRunning() else { return }
        squish.set(stretch: 0, motion: 0)
    }

    func stopSquish() { squish.set(stretch: 0, motion: 0) }

    /// Stop the audio hardware in the background. While the app is active the
    /// engine stays up: restarting it on demand dropped short cues (the first
    /// tap after a pause was silent while the output woke up).
    func suspend() {
        squish.set(stretch: 0, motion: 0)
        if engine.isRunning { engine.stop() }
    }

    private func ensureRunning() -> Bool {
        let session = AVAudioSession.sharedInstance()
        // While a conversation is being recorded the session belongs to the
        // recorder; stay quiet so cues don't end up in the transcript.
        if session.category == .playAndRecord { return false }
        if !sessionReady || session.category != .ambient {
            do {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                sessionReady = true
            } catch {
                return false
            }
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        return true
    }
}

/// The live squish voice: a low, watery slosh whose pitch and brightness follow the stretch
/// and whose loudness follows how fast the finger moves, so holding still is
/// nearly silent. Parameters are written from the main thread and read, smoothed,
/// on the audio thread (aligned Float writes, no locks, no allocation).
final class SquishVoice {
    private let params: UnsafeMutablePointer<Float> // [stretch, motion]
    private let state: UnsafeMutablePointer<Float>  // [phase, wobble, amp, freq, lp1, lp2], audio thread only
    private(set) var isActive = false

    init() {
        params = .allocate(capacity: 2)
        params.initialize(repeating: 0, count: 2)
        state = .allocate(capacity: 6)
        state.initialize(repeating: 0, count: 6)
        state[3] = 110
    }

    deinit {
        params.deallocate()
        state.deallocate()
    }

    func set(stretch: Double, motion: Double) {
        params[0] = Float(max(0, min(1, stretch)))
        params[1] = Float(max(0, min(1, motion)))
        isActive = stretch > 0.001
    }

    func makeNode(sampleRate: Double) -> AVAudioSourceNode {
        Self.node(params: params, state: state, sampleRate: sampleRate)
    }

    private static func node(params: UnsafeMutablePointer<Float>, state: UnsafeMutablePointer<Float>,
                             sampleRate: Double) -> AVAudioSourceNode {
        let sr = Float(sampleRate)
        let smooth = 1 - exp(-1 / (0.025 * sr)) // about 25 ms
        let twoPi = Float.pi * 2
        return AVAudioSourceNode { isSilence, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let stretch = params[0], motion = params[1]
            var phase = state[0], wobble = state[1], amp = state[2], freq = state[3]
            var lp1 = state[4], lp2 = state[5]
            defer { state[0] = phase; state[1] = wobble; state[2] = amp; state[3] = freq; state[4] = lp1; state[5] = lp2 }
            let targetAmp = 0.2 * stretch.squareRoot() * (0.15 + 0.85 * motion)
            let targetFreq = 98 + 150 * stretch // G2 up to about D3/E3
            // The filter opens as it stretches: muffled slosh to a brighter one
            let cutoff = 450 + 1100 * stretch
            let k = 1 - exp(-twoPi * cutoff / sr)
            if targetAmp < 0.0005 && amp < 0.0005 {
                amp = 0
                for buffer in buffers {
                    memset(buffer.mData, 0, Int(buffer.mDataByteSize))
                }
                isSilence.pointee = true
                return noErr
            }
            for frame in 0..<Int(frameCount) {
                amp += (targetAmp - amp) * smooth
                freq += (targetFreq - freq) * smooth
                wobble += twoPi * 4.5 / sr
                if wobble > twoPi { wobble -= twoPi }
                let f = freq * (1 + 0.05 * sin(wobble))
                phase += twoPi * f / sr
                if phase > twoPi { phase -= twoPi }
                // Warm harmonics so phone speakers still carry the low body, plus a liquid ripple
                let raw = (0.35 * sin(phase * 0.5) + sin(phase) + 0.5 * sin(2 * phase) + 0.22 * sin(3 * phase))
                    * (0.8 + 0.2 * sin(wobble * 2)) * amp
                lp1 += k * (raw - lp1)
                lp2 += k * (lp1 - lp2)
                let s = lp2
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = s
                }
            }
            return noErr
        }
    }
}
