import SwiftUI

/// A small "recording" pill for the badge screen: a live microphone level
/// meter (a few bars that move with the voices in the room) and the elapsed
/// time (mm:ss) since the recording started.
struct RecordingIndicator: View {
    var startedAt: Date
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            LevelMeter()
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(Self.elapsed(from: startedAt, to: context.date))
                    .font(theme.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.ink)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.surface.opacity(0.92), in: Capsule())
        .shadow(color: theme.shadowColor, radius: theme.shadowRadius, y: theme.shadowY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityValue(Self.elapsed(from: startedAt, to: Date()))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Bars that rise with the microphone level. Reads the level itself, so only
/// these bars redraw 20 times a second, not the whole badge. Silence keeps them
/// low and still; with Reduce Motion they move together, without the ripple.
private struct LevelMeter: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much each bar answers the level: tallest in the middle, like a voice.
    private static let weights: [Double] = [0.55, 0.85, 1, 0.75, 0.5]
    private static let height: CGFloat = 14

    var body: some View {
        let level = env.badge.micLevel
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || level < 0.02)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(Self.weights.indices, id: \.self) { i in
                    // Each bar flickers a little out of step with the others while someone speaks
                    let wobble = reduceMotion ? 1 : 0.75 + 0.25 * sin(t * (9 + Double(i) * 2.3) + Double(i) * 1.7)
                    let fill = 0.16 + 0.84 * min(1, level * Self.weights[i] * wobble * 1.25)
                    Capsule()
                        .fill(theme.recordingDot.opacity(0.55 + 0.45 * level))
                        .frame(width: 3, height: max(3, Self.height * CGFloat(fill)))
                }
            }
            .frame(height: Self.height)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: level)
    }
}

extension View {
    /// Shows the recording pill at the top of the badge while a conversation is recorded.
    func recordingIndicator(_ startedAt: Date?) -> some View {
        overlay(alignment: .top) {
            if let startedAt {
                RecordingIndicator(startedAt: startedAt).padding(.top, 10)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: startedAt)
    }
}
