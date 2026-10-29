import SwiftUI
import PhotosUI

/// Settings > What I share: the things you can share with people you meet.
/// Nothing goes out on its own: you pick what to share on a person's page, or
/// when you approve their request. "Include by default" preselects an item.
struct ShareSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var editing: EditTarget?

    var body: some View {
        let sharing = env.sharing
        Form {
            Section {
                if sharing.items.isEmpty {
                    Text("Nothing yet. Add your LinkedIn, a website, your email or a QR code, then share them with people you meet.")
                        .font(theme.body).foregroundStyle(theme.inkSecondary)
                }
                ForEach(sharing.items) { item in
                    ShareItemRow(item: item) { editing = EditTarget(draft: draft(for: item), photoURL: item.photoURL) }
                }
                .onDelete { offsets in
                    let gone = offsets.map { sharing.items[$0] }
                    Feedback.shared.play(.buttonPress)
                    Task { for item in gone { await sharing.remove(item) } }
                }
                .onMove { source, destination in
                    Task { await sharing.move(from: source, to: destination) }
                }
                addMenu
            } header: {
                Text("What I share")
            } footer: {
                Text("Shared only when you say so: from a person's page (Share my info), or when you approve their request. Items with Default on are picked for you; you can change the pick each time. Editing an item updates it for everyone you shared it with, and deleting it stops sharing it.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("What I share")
        .toolbar {
            if !sharing.items.isEmpty { EditButton() }
        }
        .sheet(item: $editing) { target in
            ShareItemEditor(draft: target.draft, existingPhoto: target.photoURL)
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(ShareKind.allCases) { kind in
                Button(kind.displayName, systemImage: kind.systemImage) {
                    Feedback.shared.play(.buttonPress)
                    editing = EditTarget(draft: ShareItemDraft(kind: kind), photoURL: nil)
                }
            }
        } label: {
            Label("Add something to share", systemImage: "plus.circle.fill")
                .font(theme.body.weight(.semibold))
        }
        .accessibilityIdentifier("Add something to share")
    }

    private func draft(for item: ShareItem) -> ShareItemDraft {
        ShareItemDraft(id: item.id, kind: item.shareKind, label: item.label == item.shareKind.displayName ? "" : item.label,
                       value: item.value ?? "", includeByDefault: item.includeByDefault)
    }

    struct EditTarget: Identifiable {
        let id = UUID()
        var draft: ShareItemDraft
        var photoURL: URL?
    }
}

/// One item in Settings: what it is, its value, and the Default switch.
private struct ShareItemRow: View {
    let item: ShareItem
    var onEdit: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    ShareItemIcon(kind: item.shareKind, photoURL: item.photoURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label).font(theme.headline).foregroundStyle(theme.strongInk)
                        if let value = item.value?.nilIfBlank {
                            Text(value).font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit")
            Toggle("Default", isOn: Binding(
                get: { item.includeByDefault },
                set: { on in
                    Feedback.shared.play(.toggle(on: on))
                    Task { await env.sharing.setDefault(item, on) }
                }
            ))
            .labelsHidden()
            .accessibilityLabel("Include \(item.label) by default")
        }
    }
}

/// The kind's symbol on a cream tile, or the image itself for image items.
struct ShareItemIcon: View {
    var kind: ShareKind
    var photoURL: URL?
    var size: CGFloat = 36
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let photoURL {
                AsyncImage(url: photoURL) { $0.resizable().scaledToFill() } placeholder: { theme.surfaceMuted }
            } else {
                Image(systemName: kind.systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(theme.strongInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.surfaceMuted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius * size / 48))
    }
}

/// Add or edit one item.
struct ShareItemEditor: View {
    @State var draft: ShareItemDraft
    var existingPhoto: URL?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: Data?
    @State private var preview: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if draft.kind == .image {
                        imagePicker
                    } else {
                        valueField
                    }
                    TextField(draft.kind == .image ? "Name, e.g. My QR code" : "Name (optional), e.g. Portfolio", text: $draft.label)
                        .textInputAutocapitalization(.words)
                } header: {
                    Label(draft.kind.displayName, systemImage: draft.kind.systemImage)
                }
                Section {
                    Toggle("Include by default", isOn: $draft.includeByDefault)
                        .onChange(of: draft.includeByDefault) { _, on in Feedback.shared.play(.toggle(on: on)) }
                } footer: {
                    Text("Default items are picked for you when you share. You still choose each time.")
                }
                if let error = env.sharing.lastError {
                    Section { Text(error).font(theme.caption).foregroundStyle(theme.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(draft.id == nil ? "Add" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if env.sharing.isBusy {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await env.sharing.save(draft, image: image) {
                                    Feedback.shared.play(.saved)
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
            .onAppear { env.sharing.lastError = nil }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    image = await ImagePrep.jpeg(from: item, maxSide: 1400)
                    preview = image.flatMap(UIImage.init(data:))
                    pickerItem = nil
                }
            }
        }
    }

    private var canSave: Bool {
        draft.kind == .image ? (image != nil || existingPhoto != nil) : draft.value.nilIfBlank != nil
    }

    @ViewBuilder
    private var valueField: some View {
        let field = TextField(draft.kind.placeholder, text: $draft.value)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier("Share value")
        switch draft.kind {
        case .email: field.keyboardType(.emailAddress).textContentType(.emailAddress)
        case .phone: field.keyboardType(.phonePad).textContentType(.telephoneNumber)
        case .website, .link, .linkedin: field.keyboardType(.URL).textContentType(.URL)
        default: field
        }
    }

    private var imagePicker: some View {
        HStack(spacing: 14) {
            Group {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else if let existingPhoto {
                    AsyncImage(url: existingPhoto) { $0.resizable().scaledToFill() } placeholder: { theme.surfaceMuted }
                } else {
                    Image(systemName: "qrcode").font(.system(size: 28)).foregroundStyle(theme.inkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.surfaceMuted)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius))
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(preview == nil && existingPhoto == nil ? "Choose from Photos" : "Choose another")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
