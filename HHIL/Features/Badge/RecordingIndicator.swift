import SwiftUI

/// A small "recording" pill for the badge screen: a pulsing red dot and the
/// elapsed time (mm:ss) since the recording started.
struct RecordingIndicator: View {
    var startedAt: Date
    @Environment(\.theme) private var theme
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.recordingDot)
                .frame(width: 9, height: 9)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
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
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
