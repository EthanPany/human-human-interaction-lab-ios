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
    private var idleStop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        var ids: [SoundID] = [.tap, .press, .tab, .toggleOn, .toggleOff, .wear, .takeOff, .poke, .pop, .land,
                              .boingSmall, .boingBig, .chime, .talk, .celebrate, .error]
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
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.sessionReady = false }
        })
    }

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

    /// Stop the audio hardware when quiet, and on background.
    func suspend() {
        idleStop?.cancel()
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
        scheduleIdleStop()
        return true
    }

    private func scheduleIdleStop() {
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.squish.isActive else { return }
            if self.engine.isRunning { self.engine.stop() }
        }
    }
}

/// The live squish voice: a soft rubbery tone whose pitch follows the stretch
/// and whose loudness follows how fast the finger moves, so holding still is
/// nearly silent. Parameters are written from the main thread and read, smoothed,
/// on the audio thread (aligned Float writes, no locks, no allocation).
final class SquishVoice {
    private let params: UnsafeMutablePointer<Float> // [stretch, motion]
    private let state: UnsafeMutablePointer<Float>  // [phase, wobble, amp, freq], audio thread only
    private(set) var isActive = false

    init() {
        params = .allocate(capacity: 2)
        params.initialize(repeating: 0, count: 2)
        state = .allocate(capacity: 4)
        state.initialize(repeating: 0, count: 4)
        state[3] = 150
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
            defer { state[0] = phase; state[1] = wobble; state[2] = amp; state[3] = freq }
            let targetAmp = 0.16 * stretch.squareRoot() * (0.12 + 0.88 * motion)
            let targetFreq = 150 + 330 * stretch
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
                wobble += twoPi * 7 / sr
                if wobble > twoPi { wobble -= twoPi }
                let f = freq * (1 + 0.025 * sin(wobble))
                phase += twoPi * f / sr
                if phase > twoPi { phase -= twoPi }
                let s = (sin(phase) + 0.25 * sin(2 * phase) + 0.06 * sin(3 * phase)) * amp
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = s
                }
            }
            return noErr
        }
    }
}
