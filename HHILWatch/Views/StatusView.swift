import SwiftUI

/// The glance: me (my blob, worn or not, recording), and the person the
/// badge is reacting to: their blob, a big live distance, their top topic
/// for me, and the group when there is one.
struct StatusView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let s = store.state
        ZStack {
            WatchAurora(colors: auroraColors(s))
            ScrollView {
                VStack(spacing: 6) {
                    header(s)
                    if !store.hasState {
                        Message(title: "Waiting for your iPhone", detail: "Open HHIL on your iPhone.")
                    } else if !s.signedIn {
                        Message(title: "Not signed in", detail: "Sign in to HHIL on your iPhone.")
                    } else if let peer = s.nearest {
                        PeerGlance(peer: peer, groupCount: s.groupCount)
                    } else {
                        MeGlance(me: s.me, worn: s.worn)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .containerBackground(WatchTheme.background, for: .tabView)
    }

    private func auroraColors(_ s: WatchState) -> [Color] {
        let hexes = [s.nearest?.color, s.nearest?.pairColor ?? s.me?.color].compactMap { $0 }
        return hexes.map(Color.init(hex:))
    }

    @ViewBuilder
    private func header(_ s: WatchState) -> some View {
        HStack(spacing: 6) {
            if s.nearest != nil, let me = s.me {
                BlobView(shape: me.shape, color: me.color, seed: 1, animated: false)
                    .frame(width: 22, height: 22)
            }
            WatchPill(tint: s.worn ? WatchTheme.green.opacity(0.3) : WatchTheme.surface) {
                Circle().fill(s.worn ? WatchTheme.green : WatchTheme.inkSecondary).frame(width: 6, height: 6)
                Text(s.demo ? "Demo" : s.worn ? "Worn" : "Not worn")
            }
            if let started = s.recordingStartedAt {
                WatchPill(tint: WatchTheme.recordingDot.opacity(0.25)) {
                    Circle().fill(WatchTheme.recordingDot).frame(width: 7, height: 7)
                    Text(started, style: .timer).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recording")
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PeerGlance: View {
    var peer: WatchPeer
    var groupCount: Int

    var body: some View {
        VStack(spacing: 2) {
            BlobView(shape: peer.shape, color: peer.color, seed: peer.id.hashValue)
                .frame(height: 52)
            Text(peer.firstName)
                .font(WatchTheme.title)
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
            Text(peer.together ? "Together" : WatchSnapshot.distanceText(peer.meters))
                .font(WatchTheme.distance)
                .monospacedDigit()
                .foregroundStyle(peer.isMatch ? Color(hex: peer.pairColor ?? "#FFD55D") : WatchTheme.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: peer.meters)
                .accessibilityLabel(peer.together ? "Together" : "\(WatchSnapshot.distanceText(peer.meters)) away")
            if peer.coarse, !peer.together {
                Text("Estimated").font(WatchTheme.caption).foregroundStyle(WatchTheme.inkSecondary)
            }
            if let keyword = peer.keyword {
                Text(keyword)
                    .font(WatchTheme.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(WatchTheme.cream, in: Capsule())
                    .foregroundStyle(WatchTheme.avatarInk)
                    .lineLimit(1)
            }
            if groupCount >= 2 {
                Text("Group of \(groupCount + 1)")
                    .font(WatchTheme.caption)
                    .foregroundStyle(WatchTheme.inkSecondary)
            }
        }
    }
}

private struct MeGlance: View {
    var me: WatchAvatar?
    var worn: Bool

    var body: some View {
        VStack(spacing: 4) {
            BlobView(shape: me?.shape, color: me?.color, seed: 1)
                .frame(height: 76)
            Text(worn ? "No one near yet" : "Wear your badge")
                .font(WatchTheme.title)
                .foregroundStyle(WatchTheme.ink)
            Text(worn ? "Your wrist taps when a match comes close." : "Put your iPhone badge on full screen to start.")
                .font(WatchTheme.caption)
                .foregroundStyle(WatchTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct Message: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 6) {
            BlobView(shape: "blob", color: "#FFD55D", animated: false).frame(height: 56)
            Text(title).font(WatchTheme.title).multilineTextAlignment(.center)
            Text(detail).font(WatchTheme.caption).foregroundStyle(WatchTheme.inkSecondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}
