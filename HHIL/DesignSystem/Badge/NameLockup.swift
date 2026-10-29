import SwiftUI

/// The name as display type: first name on its own line at full size, the rest
/// of the name a step smaller and tucked up close under it, then the company.
/// Both lines come down in size together until they fit the width (SwiftUI
/// measures the candidates), so a long name like "Alexandria Montgomery" keeps
/// its hierarchy instead of each line shrinking on its own.
struct NameLockup: View {
    var name: String
    var company: String?
    /// First name size before fitting.
    var size: CGFloat
    /// Largest company size.
    var companySize: CGFloat
    var ink: Color
    var companyInk: Color
    /// Lighter weights for the photo beside layout.
    var weight: Font.Weight?
    var lastWeight: Font.Weight?

    @Environment(\.theme) private var theme

    /// Scales tried in order, largest first.
    private static let scales: [CGFloat] = Array(stride(from: 1.0, through: 0.3, by: -0.05))

    var body: some View {
        let parts = Self.split(name)
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                ForEach(Self.scales, id: \.self) { scale in
                    lines(parts, scale: scale, last: scale == Self.scales.last)
                }
            }
            if let company {
                let size = min(companySize, size * theme.nameCompanyRatio)
                Text(company)
                    .font(.brandFixed(size, .medium))
                    .foregroundStyle(companyInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, size * 0.3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var firstWeight: Font.Weight { weight ?? theme.nameWeight }
    private var secondWeight: Font.Weight { lastWeight ?? theme.nameLastWeight }

    private func lines(_ parts: (first: String, last: String?), scale: CGFloat, last isFallback: Bool) -> some View {
        let first = size * scale
        return VStack(alignment: .leading, spacing: 0) {
            line(parts.first, size: first, weight: firstWeight, fallback: isFallback)
            if let last = parts.last {
                line(last, size: first * theme.nameLastRatio, weight: secondWeight, fallback: isFallback)
                    .padding(.top, first * theme.nameLineGap)
            }
        }
    }

    /// Each candidate keeps its natural width so ViewThatFits can judge it;
    /// only the smallest one may squeeze further.
    @ViewBuilder
    private func line(_ text: String, size: CGFloat, weight: Font.Weight, fallback: Bool) -> some View {
        let t = Text(text)
            .font(.brandFixed(size, weight))
            .tracking(size * theme.nameTracking)
            .foregroundStyle(ink)
            .lineLimit(1)
        if fallback {
            t.minimumScaleFactor(0.5)
        } else {
            t.fixedSize(horizontal: true, vertical: false)
        }
    }

    /// First word on top, everything after it on the second line.
    static func split(_ name: String) -> (first: String, last: String?) {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return (name, nil) }
        let rest = words.dropFirst().joined(separator: " ")
        return (first, rest.isEmpty ? nil : rest)
    }
}

#Preview("Long names") {
    VStack(spacing: 12) {
        ForEach(["Ethan Pan", "Alexandria Montgomery", "Bartholomew", "Mary Jane Watson-Fitzgerald"], id: \.self) { name in
            NameLockup(name: name, company: "Cal Hacks", size: 96, companySize: 26,
                       ink: .black, companyInk: .black.opacity(0.7))
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
        }
    }
    .padding(16)
    .frame(width: 402)
    .background(Color(hex: "#FEF3D4"))
}
