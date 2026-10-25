import SwiftUI
import UIKit

/// General Sans (Fontshare, ITF Free Font License). The font files are not in
/// git (the license forbids redistribution): run scripts/fetch-fonts.sh once.
/// Without them every brand font falls back to the system font.
enum BrandFont {
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "GeneralSans-Bold"
        case .semibold: return "GeneralSans-Semibold"
        case .medium: return "GeneralSans-Medium"
        default: return "GeneralSans-Regular"
        }
    }

    static let isAvailable = UIFont(name: "GeneralSans-Regular", size: 12) != nil

    /// The UIKit font behind `Font.brandFixed`, for measuring text before drawing it.
    static func uiFont(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        if isAvailable, let font = UIFont(name: name(for: weight), size: size) { return font }
        let system: UIFont.Weight
        switch weight {
        case .bold, .heavy, .black: system = .bold
        case .semibold: system = .semibold
        case .medium: system = .medium
        default: system = .regular
        }
        return .systemFont(ofSize: size, weight: system)
    }

    /// How wide one line of text is in the brand font, with the given tracking.
    static func width(of text: String, size: CGFloat, weight: Font.Weight, tracking: CGFloat = 0) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: uiFont(size, weight), .kern: tracking]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}

extension Font {
    /// Brand font at a fixed size that still scales with Dynamic Type.
    static func brand(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        BrandFont.isAvailable
            ? .custom(BrandFont.name(for: weight), size: size)
            : .system(size: size, weight: weight)
    }

    /// Brand font that does not scale (badge display type sized to the screen).
    static func brandFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        BrandFont.isAvailable
            ? .custom(BrandFont.name(for: weight), fixedSize: size)
            : .system(size: size, weight: weight)
    }
}
