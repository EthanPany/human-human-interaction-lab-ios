import SwiftUI

/// All visual decisions in one value. Screens read colors, fonts, radii and the
/// badge style from here, so a new look is a new Theme, not edits across views.
/// Values follow the designer's Figma page ("Profile final").
struct Theme {
    // Surfaces
    var background = Color(hex: "#FEF3D4")      // cream
    var surface = Color.white
    var surfaceMuted = Color(hex: "#FEF3D4")    // chips and icon buttons
    var ink = Color(hex: "#2C2C2C")
    var inkSecondary = Color(hex: "#2C2C2C").opacity(0.62)
    var strongInk = Color.black

    // Palette
    var red = Color(hex: "#FF6C6E")
    var yellow = Color(hex: "#FFEA82")
    var yellowStrong = Color(hex: "#FFD55D")
    var purple = Color(hex: "#EB8FFF")
    var green = Color(hex: "#A9F48E")
    var blue = Color(hex: "#87D9FB")
    var plezi = Color(hex: "#509DF8")

    /// Colors cycled for photo frames and accents.
    var accents: [Color] { [blue, purple, plezi, green, red, yellow] }

    /// The flowing background (from the designer's blurred shapes).
    var backgroundPalette: [Color] = [
        "#9CD9FF", "#A5C3FB", "#EB8FFF", "#FAB2F7",
        "#FFEA82", "#F8CD4C", "#FAA752", "#FA9E96",
        "#FF6C6E", "#F7A8AB", "#CAFFCC", "#87D9FB",
        "#F8B2AE", "#FFEA82", "#A5C3FB", "#EB8FFF",
    ].map(Color.init(hex:))

    // Shape and spacing
    var cornerRadius: CGFloat = 16
    var smallRadius: CGFloat = 12
    var badgeCornerRadius: CGFloat = 40
    var spacing: CGFloat = 20
    var screenPadding: CGFloat = 18

    // Type (General Sans, falls back to the system font if not bundled)
    var largeTitle = Font.brand(34, .semibold)
    var title = Font.brand(24)
    var headline = Font.brand(17, .semibold)
    var body = Font.brand(16)
    var caption = Font.brand(12)

    /// How the badge itself is drawn (window and worn).
    var badgeStyle: any BadgeStyle = PlayfulBadgeStyle()

    static let playful = Theme()
}

extension EnvironmentValues {
    @Entry var theme: Theme = .playful
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
