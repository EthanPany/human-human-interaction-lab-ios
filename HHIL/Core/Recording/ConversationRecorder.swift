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
    private var finishedSegments: [String] = []
    private var currentSegment = ""
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

    func start() async {
        guard !isRecording, await Self.requestPermissions(), recognizer?.isAvailable == true else { return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            lock.withLock {
                finishedSegments = []
                currentSegment = ""
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
        let text: String = lock.withLock {
            request?.endAudio()
            task?.finish()
            request = nil
            task = nil
            recording = false
            return (finishedSegments + [currentSegment]).joined(separator: " ")
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func startSegment() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        let task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let text = result?.bestTranscription.formattedString else { return }
            self.lock.withLock { self.currentSegment = text }
        }
        lock.withLock {
            self.request = request
            self.task = task
        }
    }

    private func rotateSegment() {
        guard isRecording else { return }
        lock.withLock {
            request?.endAudio()
            task?.finish()
            if !currentSegment.isEmpty { finishedSegments.append(currentSegment) }
            currentSegment = ""
        }
        startSegment()
    }
}
