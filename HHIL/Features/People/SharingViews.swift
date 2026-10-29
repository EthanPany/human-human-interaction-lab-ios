import SwiftUI

// MARK: Approval card

/// A share request waiting for me: they offer their info, or ask for mine.
/// In the People list (top) and on their page.
struct ShareRequestCard: View {
    let request: ShareRequest
    /// Who it is from (the inbox sends it; the person page knows it).
    var fromName: String
    var from: SharePerson?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var picking: PickMode?

    enum PickMode: String, Identifiable {
        case shareForAsk, shareBack
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let from {
                    PersonPhoto(url: from.profilePhotoURL, avatar: from.avatar, seed: AvatarStyle.seed(from.id))
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.isOffer ? "\(fromName) wants to share their info" : "\(fromName) asks for your info")
                        .font(theme.headline).foregroundStyle(theme.strongInk)
                    Text("\(request.createdDate, style: .relative) ago")
                        .font(theme.caption).foregroundStyle(theme.inkSecondary)
                }
            }
            if request.isOffer && !request.items.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(request.items) { TagChip(text: $0.label, systemImage: $0.shareKind.systemImage, size: 13) }
                }
            } else if !request.isOffer {
                Text("You pick what to share. Nothing is sent until you approve.")
                    .font(theme.caption).foregroundStyle(theme.inkSecondary)
            }
            HStack(spacing: 10) {
                if request.isOffer {
                    Button("Accept") { Task { await env.sharing.respond(request, approve: true) } }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Share mine back") { picking = .shareBack }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Choose and share") { picking = .shareForAsk }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button("Decline") { Task { await env.sharing.respond(request, approve: false) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.yellow, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Share request")
        .sheet(item: $picking) { mode in
            SharePickSheet(
                title: mode == .shareForAsk ? "Share with \(fromName)" : "Accept and share back",
                message: mode == .shareForAsk
                    ? "\(fromName) sees only what you pick. You can stop sharing any time on their page."
                    : "You get \(fromName)'s info, and they get what you pick here.",
                confirm: mode == .shareForAsk ? "Share" : "Accept and share",
                initial: Set(env.sharing.defaultItemIds)
            ) { ids in
                await env.sharing.respond(request, approve: true, itemIds: ids)
            }
        }
    }
}

// MARK: Picking items

/// Choose which of my items to share (defaults preselected).
struct SharePickSheet: View {
    var title: String
    var message: String
    var confirm: String
    var initial: Set<String>
    /// True when it worked (the sheet closes).
    var onConfirm: ([String]) async -> Bool
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var picked: Set<String> = []
    @State private var loaded = false

    var body: some View {
        let items = env.sharing.items
        NavigationStack {
            Form {
                Section {
                    Text(message).font(theme.body).foregroundStyle(theme.inkSecondary)
                }
                Section("What I share") {
                    if items.isEmpty {
                        Text("You haven't added anything to share yet.")
                            .font(theme.body).foregroundStyle(theme.inkSecondary)
                    }
                    ForEach(items) { item in
                        Button {
                            Feedback.shared.play(.toggle(on: !picked.contains(item.id)))
                            if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) }
                        } label: {
                            HStack(spacing: 12) {
                                ShareItemIcon(kind: item.shareKind, photoURL: item.photoURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label).font(theme.headline).foregroundStyle(theme.strongInk)
                                    if let value = item.value?.nilIfBlank {
                                        Text(value).font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: picked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(picked.contains(item.id) ? theme.plezi : theme.inkSecondary)
                            }
                        }
                        .accessibilityAddTraits(picked.contains(item.id) ? .isSelected : [])
                    }
                    NavigationLink("Edit what I share") { ShareSettingsView() }
                }
                if let error = env.sharing.lastError {
                    Section { Text(error).font(theme.caption).foregroundStyle(theme.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if env.sharing.isBusy {
                        ProgressView()
                    } else {
                        Button(confirm) {
                            let ids = items.map(\.id).filter { picked.contains($0) }
                            Task { if await onConfirm(ids) { dismiss() } }
                        }
                        .fontWeight(.semibold)
                        .disabled(picked.isEmpty)
                    }
                }
            }
            .onAppear {
                env.sharing.lastError = nil
                if !loaded { picked = initial; loaded = true }
            }
            .onChange(of: items.map(\.id)) { _, ids in
                // A new item added from "Edit what I share" starts picked if it is a default
                for item in items where item.includeByDefault && !initial.contains(item.id) && ids.contains(item.id) {
                    picked.insert(item.id)
                }
            }
        }
    }
}

// MARK: The person page block

/// On a person's page: what they share with me, what I share with them, and
/// the Share my info / Request their info buttons. Live (`sharing:with`).
struct PersonSharingCard: View {
    let personId: String
    var name: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var state = SharingWith.empty
    @State private var loaded = false
    @State private var picking = false
    @State private var confirmRevoke = false
    @State private var viewing: ShareItem?

    var body: some View {
        VStack(spacing: 12) {
            if let incoming = state.incoming {
                ShareRequestCard(request: incoming, fromName: name)
            }
            Card {
                SectionHeader(title: "Contact info") {
                    if !state.theirs.isEmpty {
                        TagChip(text: "Shared with you", systemImage: "checkmark.seal.fill", size: 12, fill: theme.green)
                    }
                }
                if !state.theirs.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(state.theirs) { item in SharedItemRow(item: item) { viewing = item } }
                    }
                } else if loaded {
                    Text("\(name) hasn't shared contact info with you. Ask, or share yours first.")
                        .font(theme.body).foregroundStyle(theme.inkSecondary)
                }
                mineStatus
                buttons
                if let error = env.sharing.lastError, picking == false {
                    Text(error).font(theme.caption).foregroundStyle(theme.red)
                }
            }
        }
        .task(id: personId) { await load() }
        .sheet(isPresented: $picking) {
            SharePickSheet(
                title: "Share with \(name)",
                message: "\(name) gets a card to accept. They see only what you pick, and you can stop sharing any time.",
                confirm: state.mine.isEmpty ? "Send" : "Update",
                initial: Set(state.mine.isEmpty ? env.sharing.defaultItemIds : state.mine)
            ) { ids in
                await env.sharing.offer(to: personId, itemIds: ids)
            }
        }
        .sheet(item: $viewing) { item in
            FullScreenImage(url: item.photoURL, title: item.label)
        }
        .confirmationDialog("Stop sharing with \(name)?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) {
                Feedback.shared.play(.buttonPress)
                Task { await env.sharing.revoke(personId) }
            }
        } message: {
            Text("\(name) will no longer see your contact info here.")
        }
    }

    @ViewBuilder
    private var mineStatus: some View {
        if let out = state.outgoing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(out.isOffer ? "Waiting for \(name) to accept your info" : "Waiting for \(name) to answer your request")
                    .font(theme.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Button("Cancel") { Task { await env.sharing.cancel(out) } }
                    .font(theme.caption.weight(.semibold))
            }
        } else if let declined = state.lastDeclinedAt, state.theirs.isEmpty,
                  Date().timeIntervalSince1970 * 1000 - declined < 24 * 3600 * 1000 {
            Text("\(name) declined your last request.").font(theme.caption).foregroundStyle(theme.inkSecondary)
        }
        if !state.mine.isEmpty {
            let count = state.mine.count
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(theme.inkSecondary)
                Text("You share \(count == 1 ? "1 item" : "\(count) items") with \(name)")
                    .font(theme.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Button("Revoke") { confirmRevoke = true }
                    .font(theme.caption.weight(.semibold))
                    .foregroundStyle(theme.red)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(state.mine.isEmpty ? "Share my info" : "Change what I share", systemImage: "square.and.arrow.up") {
                env.sharing.lastError = nil
                picking = true
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(state.outgoing?.isOffer == true)
            if state.theirs.isEmpty && state.outgoing == nil {
                Button("Request their info", systemImage: "hand.wave") {
                    Feedback.shared.play(.buttonPress)
                    Task { await env.sharing.ask(personId) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func load() async {
        guard let userId = env.session.userId else { return }
        do {
            for try await s in env.backend.sharing(userId: userId, otherId: personId) {
                // Their info just arrived: the saved chime
                if loaded && state.theirs.isEmpty && !s.theirs.isEmpty { Feedback.shared.play(.saved) }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { state = s }
                loaded = true
            }
        } catch {
            print("sharing stream ended:", error)
        }
    }
}

/// One shared item: a tappable link, or an image that opens full screen.
struct SharedItemRow: View {
    let item: ShareItem
    var onViewImage: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            Feedback.shared.play(.tap)
            if item.isImage { onViewImage() } else if let url = item.linkURL { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                ShareItemIcon(kind: item.shareKind, photoURL: item.photoURL, size: item.isImage ? 56 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).font(theme.headline).foregroundStyle(theme.strongInk)
                    Text(item.isImage ? "Tap to view" : (item.value ?? ""))
                        .font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: item.isImage ? "arrow.up.left.and.arrow.down.right" : "arrow.up.right")
                    .font(theme.caption).foregroundStyle(theme.inkSecondary)
            }
            .padding(10)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: theme.smallRadius))
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            if let value = item.value {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
            }
        }
        .accessibilityLabel("\(item.label), \(item.isImage ? "image" : item.value ?? "")")
    }
}
