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
