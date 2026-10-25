import SwiftUI

/// The white card with the big name. Used by the badge and the Profile tab.
///
/// Three layouts, each with its own typography:
///   avatar     huge semibold name, the living avatar peeking from the top right
///   photoText  photo on the right, name a size smaller and allowed two lines
///   photo      full bleed photo, bold white name over a soft shade
struct IdentityCard: View {
    var c: BadgeConfiguration
    /// 1 = the designer's 402 pt wide phone frame.
    var scale: CGFloat
    var nameSize: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch c.layout {
            case .photo where c.photoURL != nil:
                fullPhoto
            case .photoText where c.photoURL != nil:
                photoBeside
            default:
                avatarCard
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius * scale * 1.4))
    }

    // MARK: Layouts

    private var avatarCard: some View {
        GeometryReader { geo in
            // Alone, the avatar peeks big from the top right. Once we meet, the
            // stage moves to the middle and shrinks to the card's width so both
            // avatars land inside the card instead of the peer being cut off.
            let side = c.hasMet ? min(geo.size.height * 1.05, geo.size.width * 0.85) : geo.size.height * 1.05
            let x = c.hasMet ? geo.size.width / 2 : geo.size.width - geo.size.height * 0.42
            ZStack(alignment: .bottomLeading) {
                theme.surface
                stage
                    .frame(width: side, height: side)
                    .position(x: x, y: geo.size.height * 0.38)
                    .animation(.spring(response: 0.7, dampingFraction: 0.62), value: c.hasMet)
                details(nameFont: .brandFixed(nameSize, .semibold), ink: theme.strongInk, lines: 1)
                    .padding(18 * scale)
            }
        }
    }

    private var photoBeside: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                details(nameFont: .brandFixed(nameSize * 0.78, .semibold), ink: theme.strongInk, lines: 2)
                    .padding(18 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                ZStack(alignment: .bottomLeading) {
                    photo
                        .frame(width: geo.size.width * 0.42, height: geo.size.height - 24 * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                    stage
                        .frame(width: geo.size.height * 0.42, height: geo.size.height * 0.42)
                        .offset(x: -geo.size.height * 0.16, y: geo.size.height * 0.08)
                }
                .padding(12 * scale)
            }
            .background(theme.surface)
        }
    }

    private var fullPhoto: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                photo.frame(width: geo.size.width, height: geo.size.height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                stage
                    .frame(width: geo.size.height * 0.4, height: geo.size.height * 0.4)
                    .position(x: geo.size.width - geo.size.height * 0.24, y: geo.size.height * 0.22)
                details(nameFont: .brandFixed(nameSize * 1.05, .bold), ink: .white, lines: 1)
                    .padding(18 * scale)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
        }
    }

    // MARK: Parts

    private var stage: some View {
        AvatarStage(
            avatar: c.avatar,
            color: c.avatarColor,
            expression: c.expression,
            look: c.look,
            followsTilt: c.followsTilt,
            seed: c.seed,
            peer: c.peerAvatar,
            peerSeed: c.peerSeed,
            hasMet: c.hasMet,
            peerSide: (c.look?.x ?? 1) < 0 ? -1 : 1
        )
    }

    private var photo: some View {
        AsyncImage(url: c.photoURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            c.avatar.color.opacity(0.35)
        }
    }

    private func details(nameFont: Font, ink: Color, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text(c.name)
                .font(nameFont)
                .foregroundStyle(ink)
                .lineLimit(lines)
                .minimumScaleFactor(0.45)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8 * scale) {
                if let company = c.company {
                    Text(company).font(.brandFixed(17 * scale, .medium)).foregroundStyle(ink)
                    Text("|").font(.brandFixed(17 * scale)).foregroundStyle(ink.opacity(0.5))
                }
                DynamicTitle(
                    front: c.frontTag,
                    rotation: c.titleRotation,
                    font: .brandFixed(17 * scale, c.frontTag == nil ? .regular : .semibold),
                    color: ink
                )
            }
            if let location = c.location {
                LocationPill(text: location, size: 12 * scale)
            }
        }
    }
}
