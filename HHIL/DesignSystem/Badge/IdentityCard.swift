import SwiftUI

/// The white card with the big name. Used by the badge and the Profile tab.
///
/// Just the name and company, as big as fits. Three layouts:
///   avatar     huge bold name, the living avatar peeking from the top right
///   photoText  photo on the right, name a size smaller
///   photo      full bleed photo, bold white name over a soft shade
/// The name never sits under the avatar: the avatar keeps to the room above it.
struct IdentityCard: View {
    var c: BadgeConfiguration
    /// 1 = the designer's 402 pt wide phone frame.
    var scale: CGFloat
    var nameSize: CGFloat
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 22))
    /// Room kept above the name for the avatar (and any button laid over the
    /// card's top corner). With a fixed card height the room grows to fill
    /// what the name leaves; without one the card is exactly this plus the name.
    var avatarSpace: CGFloat = 110
    /// Smallest card height (photo layouts need some height to show the photo).
    var minHeight: CGFloat = 0

    @Environment(\.theme) private var theme
    @State private var cardWidth: CGFloat = 0

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
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .animation(.easeInOut(duration: 0.8), value: c.tintStrength)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        .clipShape(shape)
    }

    private var pad: CGFloat { 18 * scale }

    // MARK: Layouts

    /// The avatar lives in the room above the name and never reaches into it,
    /// so a long name can't end up under the avatar.
    private var avatarCard: some View {
        nameUnderAvatar(ink: theme.strongInk, avatarReach: 0.85)
            .background(surface)
    }

    /// The card takes on a little of the match color as they get closer.
    private var surface: Color {
        guard let tint = c.matchColor, c.tintStrength > 0 else { return theme.surface }
        return theme.surface.mix(with: tint, by: theme.matchCardTint * c.tintStrength)
    }

    private var photoBeside: some View {
        let photoWidth = (cardWidth > 0 ? cardWidth : 360 * scale) * 0.42
        return HStack(spacing: 0) {
            name(size: nameSize * 0.78, ink: theme.strongInk, weight: .semibold, lastWeight: .medium)
                .padding(.horizontal, pad)
                .padding(.bottom, pad)
                .padding(.top, photoWidth * 0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            Color.clear
                .frame(width: photoWidth)
                .frame(maxHeight: .infinity)
                .overlay { photo }
                .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                // The avatar hangs off the photo's top corner, away from the name
                .overlay(alignment: .topLeading) {
                    stage
                        .frame(width: photoWidth * 0.5, height: photoWidth * 0.5)
                        .offset(x: -photoWidth * 0.2, y: -photoWidth * 0.06)
                }
                .padding(12 * scale)
        }
        .frame(minHeight: photoWidth * 1.15)
        .background(surface)
    }

    private var fullPhoto: some View {
        nameUnderAvatar(ink: .white, avatarReach: 0.42)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .background {
                ZStack {
                    Color.clear.overlay { photo }.clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                }
            }
    }

    /// The avatar's room on top, the name below it.
    private func nameUnderAvatar(ink: Color, avatarReach: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: avatarSpace, maxHeight: .infinity)
                .overlay { GeometryReader { geo in placedStage(in: geo.size, reach: avatarReach) } }
            name(size: nameSize, ink: ink)
                .padding(.horizontal, pad)
                .padding(.bottom, pad)
        }
    }

    /// Alone, the avatar peeks from the top right, cropped by the card's top
    /// edge when the name leaves little room. Once we meet, the stage moves to
    /// the middle of the room so both avatars land inside the card.
    private func placedStage(in room: CGSize, reach: CGFloat) -> some View {
        let w = room.width, h = room.height
        let side = c.hasMet ? min(h, w * 0.85) : min(h / 0.8, w * reach)
        let x = c.hasMet ? w / 2 : w - side * 0.4
        let y = c.hasMet ? h / 2 : min(h - side * 0.5, side * 0.42)
        return stage
            .frame(width: side, height: side)
            .position(x: x, y: y)
            .animation(.spring(response: 0.7, dampingFraction: 0.62), value: c.hasMet)
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
            peerSide: (c.look?.x ?? 1) < 0 ? -1 : 1,
            meetCount: c.meetCount,
            rippleColor: c.matchColor ?? c.avatarColor
        )
        // The wearer's own idle avatar feels the phone move (walking, shakes, stillness)
        .avatarSensesMotion(c.followsTilt)
    }

    private var photo: some View {
        AsyncImage(url: c.photoURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            c.avatar.color.opacity(0.35)
        }
    }

    /// First name biggest, the rest of the name a step down, then the company.
    private func name(size: CGFloat, ink: Color, weight: Font.Weight? = nil, lastWeight: Font.Weight? = nil) -> some View {
        NameLockup(
            name: c.name,
            company: c.company,
            size: size,
            companySize: 26 * scale,
            ink: ink,
            companyInk: ink.opacity(0.7),
            weight: weight,
            lastWeight: lastWeight
        )
    }
}
