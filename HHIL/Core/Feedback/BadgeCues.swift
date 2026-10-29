import Foundation
import UIKit

/// Turns badge state changes into cues: a chime when a match appears, a gentle
/// heartbeat that quickens and rises as they get closer (matches only; someone
/// who is not a match gets no approach cues), a low settling thump
/// when you finally meet, a warm two note when the talk starts and a little
/// celebration when you're saved. Only while the badge is on screen (worn, or
/// the Badge tab) and the app is active.
@MainActor
final class BadgeCues {
    /// Full screen badge (the heartbeat is a little louder then).
    var isWorn = false { didSet { refresh() } }
    /// The Badge tab's preview is on screen.
    var isPreviewVisible = false { didSet { refresh() } }

    /// We met and are still together: the heartbeat rests.
    var together = false { didSet { if together != oldValue { refresh() } } }

    private var mode: BadgeMode = .idle
    /// The peer is a match (only matches get the chime and the heartbeat).
    private var matched = false
    private var lastMetAt: Date?
    private var peerId: String?
    private var closeness = 0.0
    private var isActive = UIApplication.shared.applicationState != .background
    private var heartbeat: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private var isShown: Bool { (isWorn || isPreviewVisible) && isActive }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.isActive = true; self.refresh() }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.isActive = false; self.refresh() }
        })
    }

    func update(_ state: BadgeState) {
        let old = mode, oldPeer = peerId
        mode = state.mode
        matched = state.isMatch
        peerId = state.peerId
        closeness = max(0, min(1, state.closeness))

        if isShown {
            switch state.mode {
            case .match where matched && (old != .match || oldPeer != state.peerId):
                Feedback.shared.play(.matchAppears)
            case .talking where old != .talking:
                // Right after the meet moment the settling sound says it already
                if lastMetAt.map({ Date().timeIntervalSince($0) > 30 }) ?? true {
                    Feedback.shared.play(.talkStart)
                }
            case .connected where old != .connected:
                Feedback.shared.play(.saved)
            default:
                break
            }
        }
        refresh(justAppeared: old != .match)
    }

    /// The live closeness from this phone's UWB readings (BadgeStore), so the
    /// heartbeat speeds up with every step instead of once a second.
    func approach(closeness value: Double) {
        closeness = max(0, min(1, value))
    }

    /// The "we finally met" moment (BadgeStore decides when, once per meeting).
    func met() {
        lastMetAt = Date()
        together = true
        if isShown { Feedback.shared.play(.met) }
    }

    /// Signed out.
    func reset() {
        mode = .idle
        peerId = nil
        closeness = 0
        lastMetAt = nil
        together = false
        refresh()
    }

    /// Run the heartbeat only while a match approaches and the badge is shown.
    private func refresh(justAppeared: Bool = false) {
        let shouldBeat = mode == .match && matched && isShown && !together
        if !shouldBeat {
            heartbeat?.cancel()
            heartbeat = nil
            return
        }
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            // Let the match chime ring out before the first beat
            try? await Task.sleep(for: .seconds(justAppeared ? 1.2 : 0.4))
            while !Task.isCancelled, let self {
                let c = self.closeness
                Feedback.shared.play(.approachTick(closeness: c, prominent: self.isWorn))
                // 2.5 s far away down to 0.6 s at talking distance
                let interval = 2.5 - 1.9 * pow(c, 0.85)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
