import SwiftUI

/// The questions the watch asks, mirrored from the phone: share my card
/// after a handshake, record this conversation (California mode), and share
/// requests. Answers go back to the phone, which does the real work.
struct PromptView: View {
    var prompt: WatchStore.Prompt
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                switch prompt {
                case .handshake:
                    handshake
                case .consent(let c):
                    consent(c)
                case .request(let r):
                    request(r)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Handshake

    @ViewBuilder
    private var handshake: some View {
        if let peer = store.handshakeAsk {
            BlobView(shape: peer.shape, color: peer.color, seed: peer.id.hashValue).frame(height: 48)
            Text("Share your card with \(peer.firstName)?")
                .font(WatchTheme.title)
                .multilineTextAlignment(.center)
            Text("You both share what you share by default.")
                .font(WatchTheme.caption)
                .foregroundStyle(WatchTheme.inkSecondary)
                .multilineTextAlignment(.center)
            answerButtons(yes: "Approve", no: "Decline",
                          onYes: { store.approveHandshake() }, onNo: { store.declineHandshake() })
        } else if let h = store.shownHandshake {
            handshakeStatus(h)
        }
    }

    @ViewBuilder
    private func handshakeStatus(_ h: WatchHandshake) -> some View {
        switch h.status {
        case .sending, .waiting:
            ProgressView().tint(WatchTheme.yellowStrong)
            Text(h.status == .sending ? "Sharing..." : "Waiting for \(h.peerName)")
                .font(WatchTheme.title)
                .multilineTextAlignment(.center)
            Text("\(h.peerName) approves on their watch. You have 2 minutes.")
                .font(WatchTheme.caption)
                .foregroundStyle(WatchTheme.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel) {
                store.send(.cancelHandshake)
                dismiss()
            }
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(WatchTheme.green)
            Text("Cards swapped")
                .font(WatchTheme.title)
            Text(h.sharedWithMe.map { "\(h.peerName) shared \($0) \($0 == 1 ? "item" : "items"). See them on your iPhone." }
                 ?? "See \(h.peerName)'s info on your iPhone.")
                .font(WatchTheme.caption)
                .foregroundStyle(WatchTheme.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
        case .expired, .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(WatchTheme.red)
            Text(h.status == .expired ? "Not shared" : "Couldn't share")
                .font(WatchTheme.title)
            if let message = h.message {
                Text(message)
                    .font(WatchTheme.caption)
                    .foregroundStyle(WatchTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("OK") { dismiss() }
        }
    }

    // MARK: Recording consent

    @ViewBuilder
    private func consent(_ c: WatchConsent) -> some View {
        Circle().fill(WatchTheme.recordingDot).frame(width: 16, height: 16)
        Text("Record this conversation?")
            .font(WatchTheme.title)
            .multilineTextAlignment(.center)
        Text(c.isGroup
             ? "California mode is on for someone here. Recording starts only when everyone agrees."
             : "California mode is on for one of you. \(c.peerName ?? "The other person") is asked too.")
            .font(WatchTheme.caption)
            .foregroundStyle(WatchTheme.inkSecondary)
            .multilineTextAlignment(.center)
        answerButtons(yes: "Record", no: "Not now",
                      onYes: { store.answerConsent(c, agree: true) }, onNo: { store.answerConsent(c, agree: false) })
    }

    // MARK: Share requests

    @ViewBuilder
    private func request(_ r: WatchShareRequest) -> some View {
        BlobView(shape: r.fromShape, color: r.fromColor, seed: r.id.hashValue).frame(height: 44)
        Text(r.isOffer ? "\(r.fromName) wants to share their info" : "\(r.fromName) asked for your info")
            .font(WatchTheme.title)
            .multilineTextAlignment(.center)
        if r.isOffer, !r.items.isEmpty {
            Text(r.items.prefix(4).joined(separator: ", "))
                .font(WatchTheme.caption)
                .foregroundStyle(WatchTheme.inkSecondary)
                .multilineTextAlignment(.center)
        } else if !r.isOffer {
            Text("Approving shares what you share by default.")
                .font(WatchTheme.caption)
                .foregroundStyle(WatchTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        answerButtons(yes: "Approve", no: "Decline",
                      onYes: { store.answerRequest(r, approve: true) }, onNo: { store.answerRequest(r, approve: false) })
    }

    private func answerButtons(yes: String, no: String, onYes: @escaping () -> Void, onNo: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button {
                onYes()
            } label: {
                Text(yes).font(WatchTheme.body).frame(maxWidth: .infinity)
            }
            .tint(WatchTheme.yellowStrong)
            .foregroundStyle(WatchTheme.avatarInk)
            Button(role: .cancel) {
                onNo()
            } label: {
                Text(no).font(WatchTheme.body).frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }
}
