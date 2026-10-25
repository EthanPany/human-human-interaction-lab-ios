import SwiftUI

/// The name as display type: first name on its own line at full size, the rest
/// of the name a step smaller and tucked up close under it, then the company.
/// Each line is measured against the width it gets and the sizes come down
/// together, so a long name like "Alexandria Montgomery" keeps its hierarchy
/// instead of each line shrinking on its own.
struct NameLockup: View {
    var name: String
    var company: String?
    /// First name size before fitting.
    var size: CGFloat
    /// Largest company size (it also follows the fitted name down).
    var companySize: CGFloat
    var ink: Color
    var companyInk: Color
    /// Lighter weights for the photo beside layout.
    var weight: Font.Weight?
    var lastWeight: Font.Weight?

    @Environment(\.theme) private var theme
    @State private var width: CGFloat = 0

    var body: some View {
        let parts = Self.split(name)
        let fit = fitted(parts)
        VStack(alignment: .leading, spacing: 0) {
            line(parts.first, size: fit.first, weight: firstWeight)
            if let last = parts.last {
                line(last, size: fit.last, weight: secondWeight)
                    .padding(.top, fit.first * theme.nameLineGap)
            }
            if let company {
                let size = min(companySize, fit.first * theme.nameCompanyRatio)
                Text(company)
                    .font(.brandFixed(size, .medium))
                    .foregroundStyle(companyInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, size * 0.3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .combine)
    }

    private var firstWeight: Font.Weight { weight ?? theme.nameWeight }
    private var secondWeight: Font.Weight { lastWeight ?? theme.nameLastWeight }

    private func line(_ text: String, size: CGFloat, weight: Font.Weight) -> some View {
        Text(text)
            .font(.brandFixed(size, weight))
            .tracking(size * theme.nameTracking)
            .foregroundStyle(ink)
            .lineLimit(1)
            // Safety net only: the sizes below already fit the measured width.
            .minimumScaleFactor(0.5)
    }

    /// First word on top, everything after it on the second line.
    static func split(_ name: String) -> (first: String, last: String?) {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return (name, nil) }
        let rest = words.dropFirst().joined(separator: " ")
        return (first, rest.isEmpty ? nil : rest)
    }

    /// Point sizes for both lines that fit the width and keep the ratio.
    private func fitted(_ parts: (first: String, last: String?)) -> (first: CGFloat, last: CGFloat) {
        let lastSize = size * theme.nameLastRatio
        guard width > 0 else { return (size, lastSize) }
        // Text draws a hair wider than UIKit measures; keep a small margin.
        let room = width * 0.97
        func fit(_ text: String, _ size: CGFloat, _ weight: Font.Weight) -> CGFloat {
            let w = BrandFont.width(of: text, size: size, weight: weight, tracking: size * theme.nameTracking)
            return w > room ? size * room / w : size
        }
        var first = max(fit(parts.first, size, firstWeight), size * 0.3)
        guard let last = parts.last else { return (first, 0) }
        let second = min(fit(last, lastSize, secondWeight), first * theme.nameLastRatio)
        if second < first * theme.nameLastMinRatio { first = second / theme.nameLastMinRatio }
        return (first, max(second, size * 0.18))
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
