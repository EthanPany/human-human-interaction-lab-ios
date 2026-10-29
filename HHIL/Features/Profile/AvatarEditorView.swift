import SwiftUI
import PhotosUI

/// Pick your avatar's shape and color, a badge layout, and a photo.
/// Changes save right away and the live preview reacts to taps.
struct AvatarEditorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var shape: AvatarShapeKind = .blob
    @State private var colorHex = "#FF6C6E"
    @State private var customColor = Color(hex: "#FF6C6E")
    @State private var layout: BadgeLayout = .avatar
    @State private var expression: AvatarExpression = .idle
    @State private var photoItem: PhotosPickerItem?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview
                    shapes
                    colors
                    layoutPicker
                    photo
                }
                .padding(theme.screenPadding)
            }
            .background(theme.background)
            .navigationTitle("Customize badge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let jpeg = await ImagePrep.jpeg(from: item) {
                        await env.session.setPhoto(jpeg)
                        if layout == .avatar { layout = .photoText }
                    }
                    photoItem = nil
                }
            }
        }
    }

    // MARK: Sections

    private var preview: some View {
        AvatarPreview(shape: shape, colorHex: colorHex, expression: $expression)
    }

    private var shapes: some View {
        AvatarShapeGrid(selection: shape, colorHex: colorHex) { kind in
            shape = kind
            save(ProfilePatch(avatarShape: kind.rawValue))
        }
    }

    private var colors: some View {
        AvatarColorRow(selection: colorHex, customColor: $customColor, isReady: loaded) { hex in pick(hex) }
    }

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Badge layout")
            Picker("Badge layout", selection: $layout) {
                ForEach(BadgeLayout.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: layout) { _, value in
                if loaded { save(ProfilePatch(badgeLayout: value.rawValue)) }
            }
            if layout != .avatar && env.session.profile?.photoURL == nil {
                Text("Add a photo below to use this layout.").font(theme.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    private var photo: some View {
        let uploading = env.session.isUploading
        let hasPhoto = env.session.profile?.photoURL != nil
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Photo")
            HStack(spacing: 12) {
                if let url = env.session.profile?.photoURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { theme.surface }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(uploading ? "Uploading…" : hasPhoto ? "Change photo" : "Choose photo")
                }
                .buttonStyle(SecondaryButtonStyle())
                if env.session.profile?.photoURL != nil {
                    Button("Remove", role: .destructive) {
                        Task { await env.session.setPhoto(nil); layout = .avatar }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: Actions

    private func load() {
        defer { DispatchQueue.main.async { loaded = true } }
        guard let p = env.session.profile else { return }
        shape = p.avatar.shape
        colorHex = p.avatar.colorHex
        customColor = p.avatar.color
        layout = p.layout
    }

    private func pick(_ hex: String) {
        colorHex = hex
        save(ProfilePatch(avatarColor: hex))
    }

    private func save(_ patch: ProfilePatch) {
        Task { await env.session.update(patch) }
    }
}

// MARK: Pieces shared with the avatar step of onboarding

/// The live avatar on the flowing background. Tap it to try its moods.
struct AvatarPreview: View {
    var shape: AvatarShapeKind
    var colorHex: String
    @Binding var expression: AvatarExpression
    var size: CGFloat = 180
    @Environment(\.theme) private var theme

    var body: some View {
        AvatarView(shape: shape, color: Color(hex: colorHex), expression: expression, seed: 1)
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(FlowingBackground(flow: 0.8).clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius)))
            .contentShape(Rectangle())
            .onTapGesture {
                let all = AvatarExpression.allCases
                expression = all[((all.firstIndex(of: expression) ?? 0) + 1) % all.count]
            }
            .accessibilityHint("Tap to try its moods")
    }
}

/// Every avatar shape in the chosen color, the selected one outlined.
struct AvatarShapeGrid: View {
    var selection: AvatarShapeKind
    var colorHex: String
    var onPick: (AvatarShapeKind) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Shape")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(AvatarShapeKind.allCases) { kind in
                    Button {
                        onPick(kind)
                    } label: {
                        VStack(spacing: 4) {
                            AvatarView(shape: kind, color: Color(hex: colorHex), animated: false, seed: kind.hashValue)
                                .frame(width: 54, height: 54)
                            Text(kind.displayName).font(theme.caption).foregroundStyle(theme.ink)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.strongInk, lineWidth: selection == kind ? 2 : 0))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(kind.displayName)
                    .accessibilityAddTraits(selection == kind ? .isSelected : [])
                }
            }
        }
    }
}

/// The theme's avatar swatches and a custom color well.
struct AvatarColorRow: View {
    var selection: String
    @Binding var customColor: Color
    /// False while the screen loads its saved values (so the well's first value isn't a pick).
    var isReady = true
    var onPick: (String) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Color")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(theme.avatarSwatches, id: \.self) { hex in
                        Button {
                            onPick(hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().strokeBorder(theme.strongInk, lineWidth: selection == hex ? 3 : 0))
                        }
                        .accessibilityLabel("Color \(hex)")
                    }
                    ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40, height: 40)
                }
                .padding(.vertical, 4)
            }
            .onChange(of: customColor) { _, color in
                if isReady, let hex = color.hexString, hex != selection { onPick(hex) }
            }
        }
    }
}

extension Color {
    /// "#RRGGBB" for this color in sRGB, when it can be resolved.
    var hexString: String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
