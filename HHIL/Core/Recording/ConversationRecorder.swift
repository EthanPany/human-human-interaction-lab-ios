import Foundation
import AVFoundation
import Speech

/// Records the microphone and transcribes on device while two people talk.
/// Only the transcript text leaves the phone.
///
/// Not main actor bound: the audio tap runs on a background thread. Shared
/// state is guarded by a lock.
final class ConversationRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let lock = NSLock()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// One entry per recognition request; callbacks write only their own slot.
    private var segments: [String] = []
    private var finals: [Bool] = []
    private var rotateTask: Task<Void, Never>?
    private var recording = false

    var isRecording: Bool { lock.withLock { recording } }

    /// Ask for microphone and speech permission (also called from onboarding).
    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    /// Starts recording. If the calling task is cancelled while permissions or
    /// audio setup are pending, it gives up instead of leaving the mic on.
    func start() async {
        guard !isRecording, await Self.requestPermissions(), recognizer?.isAvailable == true else { return }
        guard !Task.isCancelled else { return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            lock.withLock {
                segments = []
                finals = []
            }
            startSegment()

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                guard let self else { return }
                let req = self.lock.withLock { self.request }
                req?.append(buffer)
            }
            engine.prepare()
            try engine.start()
            lock.withLock { recording = true }

            // Keep each recognition request short: roll to a new one every 50 s.
            rotateTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(50))
                    self?.rotateSegment()
                }
            }
        } catch {
            print("recording failed to start:", error)
            _ = await stop()
        }
    }

    /// Stop and return the full transcript.
    func stop() async -> String? {
        rotateTask?.cancel()
        rotateTask = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        // End the audio but let the recognizer deliver its final result.
        lock.withLock {
            request?.endAudio()
            request = nil
            recording = false
        }
        for _ in 0..<15 { // up to 1.5 s
            if lock.withLock({ finals.allSatisfy { $0 } }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let text: String = lock.withLock {
            task?.cancel()
            task = nil
            return segments.joined(separator: " ")
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        // Hand the session back to the UI sounds (ambient: the silent switch mutes them)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        // The session was deactivated above: the UI sounds must bring it back up.
        await MainActor.run { NotificationCenter.default.post(name: .audioSessionReleased, object: nil) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func startSegment() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        let index: Int = lock.withLock {
            segments.append("")
            finals.append(false)
            return segments.count - 1
        }
        let task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.lock.withLock {
                guard index < self.segments.count else { return }
                if let text = result?.bestTranscription.formattedString { self.segments[index] = text }
                if result?.isFinal == true || error != nil { self.finals[index] = true }
            }
        }
        lock.withLock {
            self.request = request
            self.task = task
        }
    }

    private func rotateSegment() {
        guard isRecording else { return }
        // End the old request (its final result still lands in its own slot)
        lock.withLock { request?.endAudio() }
        startSegment()
    }
}
