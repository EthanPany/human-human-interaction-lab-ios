import SwiftUI
import PhotosUI

/// Edit profile > Profile photo: pick from Photos or take one, crop it to a
/// square, upload. It shows in People rows and on your page for others; the
/// badge keeps your jelly avatar.
struct ProfilePhotoSection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var item: PhotosPickerItem?
    @State private var showCamera = false
    /// The photo being cropped.
    @State private var cropping: CropImage?

    var body: some View {
        let p = env.session.profile
        Section {
            HStack(spacing: 16) {
                PersonPhoto(url: p?.profilePhotoURL, avatar: p?.avatar ?? AvatarStyle(shape: nil, color: nil),
                            seed: AvatarStyle.seed(p?.id ?? "me"))
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label(p?.profilePhotoURL == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                    }
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    }
                    if p?.profilePhotoURL != nil {
                        Button(role: .destructive) {
                            Feedback.shared.play(.buttonPress)
                            Task { await env.session.setProfilePhoto(nil) }
                        } label: { Label("Remove photo", systemImage: "trash") }
                    }
                }
                .font(theme.body)
                // Several buttons in one Form row: each needs its own hit area
                .buttonStyle(.borderless)
                if env.session.isUploading { Spacer(); ProgressView() }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Profile photo")
        } footer: {
            Text("Shows in People and on your page for people you meet. Your badge keeps your avatar.")
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let image = await ImagePrep.image(from: picked) { cropping = CropImage(image: image) }
                item = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                let upright = ImagePrep.upright(image)
                // After the camera finishes closing, or the crop sheet can't present
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    cropping = CropImage(image: upright)
                }
            }
                .ignoresSafeArea()
        }
        .sheet(item: $cropping) { crop in
            SquareCropView(image: crop.image) { jpeg in
                Task { await env.session.setProfilePhoto(jpeg) }
            }
        }
    }
}

/// A picked image waiting to be cropped (sheet item).
struct CropImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
