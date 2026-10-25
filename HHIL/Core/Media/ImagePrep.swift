import SwiftUI
import PhotosUI
import UIKit

/// Turns a PhotosPicker selection into a small JPEG for upload.
enum ImagePrep {
    static func jpeg(from item: PhotosPickerItem, maxSide: CGFloat = 1200) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return nil }
        let longest = max(image.size.width, image.size.height)
        let factor = min(1, maxSide / max(longest, 1))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}
