import SwiftUI
import PhotosUI
import UIKit

extension ImagePrep {
    /// The picked photo as an upright UIImage (for cropping before upload).
    static func image(from item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data).map(upright)
    }

    /// Redraw so the pixels match the orientation (camera photos are often rotated).
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// A square JPEG of `image`, scaled by `zoom` (1: the short side fills the
    /// square) and moved by `offset` (in units of the square's side, 0 centered).
    static func squareJPEG(_ image: UIImage, zoom: CGFloat, offset: CGSize, side: CGFloat = 800) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let fill = side / min(size.width, size.height) * max(1, zoom)
        let drawn = CGSize(width: size.width * fill, height: size.height * fill)
        let origin = CGPoint(x: (side - drawn.width) / 2 + offset.width * side,
                             y: (side - drawn.height) / 2 + offset.height * side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}

/// Move and pinch a photo inside a round square frame, then use it.
struct SquareCropView: View {
    let image: UIImage
    var onDone: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) - theme.screenPadding * 2
                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    cropper(side: max(120, side))
                    Text("Drag and pinch to frame your face.")
                        .font(theme.caption).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .navigationTitle("Profile photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use photo") {
                        if let data = ImagePrep.squareJPEG(image, zoom: zoom, offset: offset) {
                            Feedback.shared.play(.saved)
                            onDone(data)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func cropper(side: CGFloat) -> some View {
        let liveZoom = clampZoom(zoom * pinch)
        let live = clamp(CGSize(width: offset.width + drag.width / side, height: offset.height + drag.height / side), zoom: liveZoom)
        let fill = side / min(image.size.width, image.size.height) * liveZoom
        return Image(uiImage: image)
            .resizable()
            .frame(width: image.size.width * fill, height: image.size.height * fill)
            .offset(x: live.width * side, y: live.height * side)
            .frame(width: side, height: side)
            .clipped()
            .overlay {
                // Round guide: what People rows show
                Rectangle().fill(theme.background.opacity(0.55))
                    .mask {
                        Rectangle().overlay(Circle().blendMode(.destinationOut))
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
                Circle().strokeBorder(theme.surface, lineWidth: 3).allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset = clamp(CGSize(width: offset.width + value.translation.width / side,
                                              height: offset.height + value.translation.height / side), zoom: zoom)
                    }
                    .simultaneously(with: MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in
                            zoom = clampZoom(zoom * value.magnification)
                            offset = clamp(offset, zoom: zoom)
                        })
            )
            .accessibilityLabel("Photo to crop")
    }

    private func clampZoom(_ z: CGFloat) -> CGFloat { min(4, max(1, z)) }

    /// Keep the photo covering the whole square.
    private func clamp(_ o: CGSize, zoom: CGFloat) -> CGSize {
        let short = min(image.size.width, image.size.height)
        let w = image.size.width / short * zoom
        let h = image.size.height / short * zoom
        let maxX = max(0, (w - 1) / 2)
        let maxY = max(0, (h - 1) / 2)
        return CGSize(width: min(maxX, max(-maxX, o.width)), height: min(maxY, max(-maxY, o.height)))
    }
}
