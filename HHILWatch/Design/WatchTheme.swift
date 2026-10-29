import SwiftUI

/// Jelly Pop on the wrist: the phone's cream and pastel palette turned dark
/// (OLED black, the pastels as glows and fills), big chunky type, round shapes.
enum WatchTheme {
    static let background = Color.black
    static let surface = Color.white.opacity(0.1)
    static let ink = Color.white
    static let inkSecondary = Color.white.opacity(0.62)
    static let cream = Color(hex: "#FEF3D4")
    static let yellowStrong = Color(hex: "#FFD55D")
    static let red = Color(hex: "#FF6C6E")
    static let blue = Color(hex: "#87D9FB")
    static let purple = Color(hex: "#EB8FFF")
    static let green = Color(hex: "#A9F48E")
    static let recordingDot = Color(hex: "#FF3B30")
    static let avatarInk = Color(hex: "#1A1A1A")
    static let defaultAvatar = "#FF6C6E"

    // The phone's General Sans isn't bundled on the watch (fetched, never
    // committed); the rounded system face keeps the chunky, friendly feel and
    // follows the wearer's text size.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.system(style, design: .rounded, weight: weight)
    }

    static let distance = Font.system(size: 40, weight: .semibold, design: .rounded)
    static let title = font(20, .semibold, relativeTo: .headline)
    static let body = font(16, .medium, relativeTo: .body)
    static let caption = font(13, .medium, relativeTo: .footnote)
}

extension Color {
    /// "#RRGGBB" -> Color. Invalid input gives gray.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        guard s.count == 6 else { self = .gray; return }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// A slow dark aurora behind the glance: the match's colors drift in the
/// corners of a black mesh (still when the screen dims).
struct WatchAurora: View {
    var colors: [Color]
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: dimmed)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let c = colors.isEmpty ? [WatchTheme.purple, WatchTheme.blue] : colors
            let a = c[0], b = c.count > 1 ? c[1] : c[0]
            let dx = Float(0.08 * sin(t * 0.35)), dy = Float(0.08 * cos(t * 0.27))
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + dx, 0.5 + dy], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    a.opacity(0.55), .black, b.opacity(0.35),
                    .black, .black, .black,
                    b.opacity(0.3), .black, a.opacity(0.4),
                ]
            )
            .opacity(dimmed ? 0.4 : 1)
        }
        .ignoresSafeArea()
    }
}

/// A small rounded pill (worn, recording, group).
struct WatchPill<Content: View>: View {
    var tint: Color = WatchTheme.surface
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .font(WatchTheme.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
    }
}
