import Foundation
import UIKit

/// Turns badge state changes into cues: a chime when a match appears, a gentle
/// heartbeat that quickens and rises as they get closer, a warm two note when
/// the talk starts and a little celebration when you're saved. Only while the
/// badge is on screen (worn, or the Badge tab) and the app is active.
@MainActor
final class BadgeCues {
    /// Full screen badge (the heartbeat is a little louder then).
    var isWorn = false { didSet { refresh() } }
    /// The Badge tab's preview is on screen.
    var isPreviewVisible = false { didSet { refresh() } }

    private var mode: BadgeMode = .idle
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
        peerId = state.peerId
        closeness = max(0, min(1, state.closeness))

        if isShown {
            switch state.mode {
            case .match where old != .match || oldPeer != state.peerId:
                Feedback.shared.play(.matchAppears)
            case .talking where old != .talking:
                Feedback.shared.play(.talkStart)
            case .connected where old != .connected:
                Feedback.shared.play(.saved)
            default:
                break
            }
        }
        refresh(justAppeared: old != .match)
    }

    /// Signed out.
    func reset() {
        mode = .idle
        peerId = nil
        closeness = 0
        refresh()
    }

    /// Run the heartbeat only while a match approaches and the badge is shown.
    private func refresh(justAppeared: Bool = false) {
        let shouldBeat = mode == .match && isShown
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
