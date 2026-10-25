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
    /// Wide screens (iPad, the unfolded Duo, landscape) lay pages out in
    /// columns: two from this width, three from the next, never wider than the cap.
    var twoColumnWidth: CGFloat = 540
    var threeColumnWidth: CGFloat = 1000
    var maxContentWidth: CGFloat = 1400
    /// Narrowest a card in a grid of people gets.
    var gridCardMinWidth: CGFloat = 300

    // Type (General Sans, falls back to the system font if not bundled)
    var largeTitle = Font.brand(34, .semibold)
    var title = Font.brand(24)
    var headline = Font.brand(17, .semibold)
    var body = Font.brand(16)
    var caption = Font.brand(12)
    /// Every section and card title ("Interests", "At this event", "Your agent", ...).
    var sectionTitleSize: CGFloat = 18
    var sectionTitle: Font { .brand(sectionTitleSize, .semibold) }
    /// Small labels above a value ("Looking for", "I can help with").
    var fieldLabel = Font.brand(13, .semibold)

    /// The name on the identity card: first name biggest, the rest of the name
    /// a step down and pulled up close under it, both tracked a little tight.
    var nameLastRatio: CGFloat = 0.64
    /// Below this last to first ratio the first name shrinks too, so a very
    /// long last name never ends up tiny under a huge first name.
    var nameLastMinRatio: CGFloat = 0.48
    /// Space between the two name lines, in first name ems (negative pulls them together).
    var nameLineGap: CGFloat = -0.12
    /// Letter spacing of the name, in ems.
    var nameTracking: CGFloat = -0.025
    /// Company under the name, relative to the first name.
    var nameCompanyRatio: CGFloat = 0.34
    var nameWeight: Font.Weight = .bold
    var nameLastWeight: Font.Weight = .semibold

    /// Avatar colors offered in setup and in the badge editor.
    var avatarSwatches: [String] = [
        "#FF6C6E", "#FFEA82", "#EB8FFF", "#A9F48E", "#87D9FB",
        "#509DF8", "#3BB52D", "#45D0DD", "#F8CD4C", "#FAA752",
    ]

    /// Buttons and pills sit close on their shadow: on the shape only, never the label.
    var shadowColor = Color.black.opacity(0.22)
    var shadowRadius: CGFloat = 0.75
    var shadowY: CGFloat = 1.5

    /// Both people's colors flowing over the badge background: this opacity
    /// when a match is first sensed (10 m), rising to the upper bound by 3 m.
    var matchWashOpacity: ClosedRange<Double> = 0.12...0.72
    /// How fast that two color blend drifts across the badge (radians per second).
    var pairWashSpeed: Double = 0.35
    /// How much of the match color the white identity card takes on at talking distance.
    var matchCardTint: Double = 0.22
    /// The recording dot on the badge screen.
    var recordingDot = Color(hex: "#FF3B30")

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
