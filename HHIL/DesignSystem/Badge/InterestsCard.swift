import SwiftUI

/// Hobbies and event tags together with photo moments, in the designer's
/// yellow block. The item a nearby match cares about is outlined and first.
struct InterestsCard<Trailing: View>: View {
    var interests: [String]
    var highlighted: String?
    var moments: [Moment]
    var scale: CGFloat
    var maxMoments: Int = 3
    var title: String = "Interests"
    /// Set on the Profile tab: long press a moment to remove it.
    var onRemoveMoment: ((Moment) -> Void)?
    @ViewBuilder var trailing: Trailing

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack {
                Text(title).font(.brandFixed(16 * scale)).foregroundStyle(theme.ink)
                Spacer()
                trailing
            }
            if !interests.isEmpty {
                FlowLayout(spacing: 10 * scale) {
                    ForEach(interests, id: \.self) { item in
                        TagChip(text: item, size: 16 * scale, highlighted: item == highlighted)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.5, bounce: 0.3), value: interests)
            }
            if !moments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14 * scale) {
                        ForEach(Array(moments.prefix(maxMoments).enumerated()), id: \.element.id) { index, moment in
                            MomentCard(moment: moment, frame: theme.accents[index % theme.accents.count], scale: scale)
                                .contextMenu {
                                    if let onRemoveMoment {
                                        Button("Remove photo", systemImage: "trash", role: .destructive) {
                                            onRemoveMoment(moment)
                                        }
                                    }
                                }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.yellow, in: RoundedRectangle(cornerRadius: theme.smallRadius * scale * 1.3))
    }
}

extension InterestsCard where Trailing == EmptyView {
    init(interests: [String], highlighted: String?, moments: [Moment], scale: CGFloat, maxMoments: Int = 3) {
        self.init(interests: interests, highlighted: highlighted, moments: moments, scale: scale,
                  maxMoments: maxMoments, onRemoveMoment: nil) { EmptyView() }
    }
}

/// A photo in a colored frame with a caption and date (the designer's "Lore" card).
struct MomentCard: View {
    var moment: Moment
    var frame: Color
    var scale: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            AsyncImage(url: moment.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.4)
            }
            .frame(width: 92 * scale, height: 112 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 10 * scale))

            if let caption = moment.caption {
                Text(caption)
                    .font(.brandFixed(11 * scale, .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .frame(width: 92 * scale, alignment: .leading)
            }
            Text(moment.date, format: .dateTime.month(.abbreviated).day())
                .font(.brandFixed(11 * scale))
                .foregroundStyle(theme.ink.opacity(0.7))
        }
        .padding(8 * scale)
        .background(frame, in: RoundedRectangle(cornerRadius: 10 * scale))
    }
}
