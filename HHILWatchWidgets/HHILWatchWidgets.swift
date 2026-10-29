import SwiftUI
import WidgetKit

// Smart Stack and complications: the nearest match's distance and whether a
// conversation is being recorded. The watch app writes a small snapshot to
// the app group (WatchSnapshot) and asks WidgetKit to reload when it changes.

struct NearestEntry: TimelineEntry {
    var date: Date
    var snapshot: WatchSnapshot?

    /// A distance older than this is no longer live; say so instead.
    static let fresh: TimeInterval = 5 * 60

    var isFresh: Bool { snapshot.map { date.timeIntervalSince($0.updatedAt) < Self.fresh } ?? false }
    var peerName: String? { isFresh ? snapshot?.peerName : nil }
    var recordingStartedAt: Date? { isFresh ? snapshot?.recordingStartedAt : nil }
}

struct NearestProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearestEntry {
        NearestEntry(date: Date(), snapshot: WatchSnapshot(peerName: "Maya", peerColor: "#3BB52D", meters: 2.4, worn: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (NearestEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : NearestEntry(date: Date(), snapshot: WatchSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearestEntry>) -> Void) {
        let now = Date()
        let snap = WatchSnapshot.load()
        var entries = [NearestEntry(date: now, snapshot: snap)]
        // Turn stale on its own if the app stops sending
        if let snap {
            let staleAt = snap.updatedAt.addingTimeInterval(NearestEntry.fresh)
            if staleAt > now { entries.append(NearestEntry(date: staleAt, snapshot: snap)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct NearestWidgetView: View {
    var entry: NearestEntry
    @Environment(\.widgetFamily) private var family

    private var tint: Color { Color(hex: entry.snapshot?.peerColor ?? "#FFD55D") }
    private var distance: String {
        guard let s = entry.snapshot, entry.peerName != nil else { return "--" }
        return s.together ? "Here" : WatchSnapshot.distanceText(s.meters)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if entry.recordingStartedAt != nil {
                        Circle().fill(Color(hex: "#FF3B30")).frame(width: 6, height: 6)
                    }
                    Text(distance).font(.system(size: 13, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                    Text(entry.peerName ?? "HHIL").font(.system(size: 9)).lineLimit(1)
                }
                .widgetAccentable()
            }
        case .accessoryInline:
            if let started = entry.recordingStartedAt {
                Text("Recording \(started, style: .timer)")
            } else if let name = entry.peerName {
                Text("\(name) \(distance)")
            } else {
                Text("No match near")
            }
        case .accessoryCorner:
            Text(distance)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .widgetLabel(entry.peerName ?? "HHIL")
        default:
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 26, height: 26).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.peerName ?? "No match near")
                        .font(.headline)
                        .lineLimit(1)
                    Text(entry.peerName == nil ? (entry.snapshot?.worn == true ? "Badge worn" : "Badge not worn") : distance)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    if let started = entry.recordingStartedAt {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: "#FF3B30")).frame(width: 6, height: 6)
                            Text(started, style: .timer).font(.caption2).monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct NearestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NearestMatch", provider: NearestProvider()) { entry in
            NearestWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Nearest match")
        .description("How far your nearest match is, and whether you are recording.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct HHILWatchWidgets: WidgetBundle {
    var body: some Widget {
        NearestWidget()
    }
}
