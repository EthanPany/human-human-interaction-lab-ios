import SwiftUI

/// All visual decisions in one value. Screens read colors, fonts, radii and the
/// badge style from here, so the designers' final look is a new Theme (and a
/// new BadgeStyle), not edits scattered across views.
struct Theme {
    // Colors
    var background = Color(hex: "#F2F2F7")
    var surface = Color.white
    var surfaceMuted = Color(hex: "#E6E6EC")
    var ink = Color(hex: "#111114")
    var inkSecondary = Color(hex: "#5E5E66")
    var accent = Color(hex: "#0060DF")
    var placeholderStroke = Color(hex: "#8A8A94")
    var badgeIdle = Color(hex: "#D6D6DE")

    // Shape and spacing
    var cornerRadius: CGFloat = 22
    var badgeCornerRadius: CGFloat = 44
    var spacing: CGFloat = 14
    var screenPadding: CGFloat = 16

    // Type
    var largeTitle = Font.system(size: 34, weight: .bold)
    var title = Font.system(size: 24, weight: .bold)
    var headline = Font.system(size: 17, weight: .semibold)
    var body = Font.system(size: 16)
    var caption = Font.system(size: 13, weight: .semibold)

    /// How the badge itself is drawn (window and worn).
    var badgeStyle: any BadgeStyle = WireframeBadgeStyle()

    static let wireframe = Theme()
}

extension EnvironmentValues {
    @Entry var theme: Theme = .wireframe
}

extension Color {
    /// "#RRGGBB" -> Color. Invalid input gives gray.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        guard s.count == 6 else { self = .gray; return }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
