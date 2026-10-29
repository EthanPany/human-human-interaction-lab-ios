import SwiftUI

/// Someone's round profile photo, or their jelly avatar when they have none
/// (also while the photo loads). People rows, person pages, approval cards.
struct PersonPhoto: View {
    var url: URL?
    var avatar: AvatarStyle
    var seed: Int
    var expression: AvatarExpression = .happy
    var animated = false
    @Environment(\.theme) private var theme

    var body: some View {
        if let url {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                jelly.padding(4)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2))
            .background(RaisedFill(shape: Circle(), fill: theme.surfaceMuted))
            .accessibilityLabel("Profile photo")
        } else {
            jelly
        }
    }

    private var jelly: some View {
        AvatarView(shape: avatar.shape, color: avatar.color, expression: expression, animated: animated, seed: seed)
    }
}

/// An image full screen (a shared QR code, a profile photo): pinch to zoom, tap Done.
struct FullScreenImage: View {
    var url: URL?
    var title: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                theme.surface.ignoresSafeArea()
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                        .scaleEffect(min(4, max(1, zoom * pinch)))
                        .gesture(MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in zoom = min(4, max(1, zoom * value.magnification)) })
                        .onTapGesture(count: 2) { withAnimation(.pressSpring) { zoom = zoom > 1 ? 1 : 2 } }
                } placeholder: {
                    ProgressView()
                }
                .padding(theme.screenPadding)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
