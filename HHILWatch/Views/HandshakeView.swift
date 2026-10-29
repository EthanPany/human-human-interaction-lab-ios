import SwiftUI

/// The handshake page: who a handshake would share with, whether the wrist
/// is listening, the manual "Shake hands" button, and a pretend handshake
/// for the simulator (Core Motion has no motion there).
struct HandshakeView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let peer = store.handshakePeer
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "hands.and.sparkles.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(WatchTheme.yellowStrong)
                Text(peer.map { "Beside \($0.firstName)" } ?? "No one within 1 m")
                    .font(WatchTheme.title)
                    .multilineTextAlignment(.center)
                Text(status(peer))
                    .font(WatchTheme.caption)
                    .foregroundStyle(WatchTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    store.shakeHandsTapped()
                } label: {
                    Label("Shake hands", systemImage: "hand.wave.fill")
                        .font(WatchTheme.body)
                }
                .tint(WatchTheme.yellowStrong)
                .foregroundStyle(WatchTheme.avatarInk)
                .disabled(peer == nil)
                if let note = store.handshakeNote {
                    Text(note).font(WatchTheme.caption).foregroundStyle(WatchTheme.blue).multilineTextAlignment(.center)
                }
                Divider().padding(.vertical, 4)
                Button("Pretend handshake") { store.simulateHandshake() }
                    .font(WatchTheme.caption)
                Button("Refresh from iPhone") { store.send(.requestState) }
                    .font(WatchTheme.caption)
            }
        }
        .containerBackground(WatchTheme.background, for: .tabView)
    }

    private func status(_ peer: WatchPeer?) -> String {
        if !store.state.handshakeEnabled { return "Handshake to share is off in Settings on your iPhone." }
        if peer == nil { return "Stand within 1 m of someone, both badges worn, then shake hands." }
        if store.monitor.isListening { return store.monitor.isAvailable ? "Shake hands to share your card." : "No motion sensor here: use the buttons." }
        return "Shake hands to share your card."
    }
}
