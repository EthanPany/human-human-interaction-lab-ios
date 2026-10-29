import SwiftUI

/// Up to four people around, closest first, with their distance.
struct NearbyView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let people = store.state.nearby
        List {
            if people.isEmpty {
                Text(store.state.worn ? "No one nearby right now." : "Wear your badge to see who is nearby.")
                    .font(WatchTheme.caption)
                    .foregroundStyle(WatchTheme.inkSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(people) { p in
                HStack(spacing: 8) {
                    BlobView(shape: p.shape, color: p.color, seed: p.id.hashValue, animated: false)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.firstName).font(WatchTheme.body).lineLimit(1)
                        if p.isMatch {
                            Text("Match").font(WatchTheme.caption).foregroundStyle(Color(hex: p.pairColor ?? "#FFD55D"))
                        }
                    }
                    Spacer(minLength: 4)
                    Text(p.together ? "Here" : WatchSnapshot.distanceText(p.meters))
                        .font(WatchTheme.body.monospacedDigit())
                        .foregroundStyle(p.coarse ? WatchTheme.inkSecondary : WatchTheme.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Nearby")
        .containerBackground(WatchTheme.background, for: .tabView)
    }
}
