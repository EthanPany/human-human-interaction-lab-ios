import SwiftUI
import UIKit

/// How proximity colors the avatar.
///
/// Nobody near: the avatar keeps its own color. As a match approaches it takes
/// on the shared match color: far away that color is pale and light, and the
/// closer they get the more saturated and deeper it becomes.
enum AvatarTint {
    static func color(own: Color, match: Color?, closeness: Double) -> Color {
        guard let match else { return own }
        let c = max(0, min(1, closeness))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(match).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let saturation = s * (0.3 + 0.75 * c)
        let brightness = min(1, b * (1.08 - 0.3 * c))
        let tinted = Color(hue: h, saturation: min(1, saturation), brightness: brightness)
        // Blend from own color into the tint so the change is gradual
        return own.mix(with: tinted, by: 0.35 + 0.65 * c)
    }

    /// The feeling that goes with the badge state.
    static func expression(mode: BadgeMode, closeness: Double, hasProfile: Bool) -> AvatarExpression {
        switch mode {
        case .idle: return hasProfile ? .idle : .sleepy
        case .match: return closeness > 0.6 ? .excited : .curious
        case .talking: return .happy
        case .connected: return .love
        }
    }
}
