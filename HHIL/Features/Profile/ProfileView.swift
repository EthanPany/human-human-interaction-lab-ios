import SwiftUI
import PhotosUI

/// Your profile, laid out like the designer's "Profile final" page: the same
/// identity card and interests block the badge uses, plus the event details.
/// Every block is optional: fill it here, or just tell your agent by text.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    @State private var editing = false
    @State private var customizing = false
    @State private var showSettings = false
    @State private var newMoment: PhotosPickerItem?
    @State private var momentCaption = ""
    @State private var pendingMoment: Data?

    var body: some View {
        let p = env.session.profile
        NavigationStack {
            ZStack {
                FlowingBackground(flow: 0.6)
                ScrollView {
                    VStack(spacing: 20) {
                        topBar
                        identity(p)
                        interests(p)
                        eventBlock(p)
                        agentBlock
                    }
                    .padding(.horizontal, theme.screenPadding)
                    .padding(.bottom, 32)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $editing) { ProfileEditView() }
            .sheet(isPresented: $customizing) { AvatarEditorView() }
            .onChange(of: newMoment) { _, item in
                guard let item else { return }
                Task {
                    pendingMoment = await ImagePrep.jpeg(from: item)
                    newMoment = nil
                }
            }
            .alert("Add a caption?", isPresented: Binding(get: { pendingMoment != nil }, set: { if !$0 { pendingMoment = nil } })) {
                TextField("Hiking with Daniel", text: $momentCaption)
                Button("Add") { saveMoment() }
                Button("Cancel", role: .cancel) { pendingMoment = nil }
            }
        }
    }

    // MARK: Blocks

    private var topBar: some View {
        HStack(spacing: 12) {
            AvatarView(shape: env.session.profile?.avatar.shape ?? .blob,
                       color: env.session.profile?.avatar.color ?? theme.red,
                       animated: false, seed: 1)
                .frame(width: 38, height: 38)
            Spacer()
            RegionPill()
            PhotosPicker(selection: $newMoment, matching: .images) {
                IconButtonLabel(systemImage: env.session.isUploading ? "hourglass" : "plus")
            }
            .accessibilityLabel("Add a photo")
            IconButton(systemImage: "slider.horizontal.3", label: "Settings") { showSettings = true }
        }
        .padding(.top, 8)
    }

    private func identity(_ p: UserProfile?) -> some View {
        IdentityCard(c: previewConfiguration(p), scale: 0.91, nameSize: 52)
            .frame(height: 230)
            .overlay(alignment: .topLeading) {
                IconButton(systemImage: "paintpalette", label: "Customize badge") { customizing = true }
                    .padding(12)
            }
            .onTapGesture { editing = true }
    }

    @ViewBuilder
    private func interests(_ p: UserProfile?) -> some View {
        let items = (p?.badgeTags ?? []) + (p?.hobbies ?? []).filter { !(p?.badgeTags ?? []).contains($0) }
        InterestsCard(
            interests: items,
            highlighted: nil,
            moments: env.session.moments,
            scale: 1,
            maxMoments: 30,
            onRemoveMoment: { moment in Task { await env.session.removeMoment(moment) } }
        ) {
            IconButton(systemImage: "pencil", label: "Edit interests") { editing = true }
        }
        if items.isEmpty && env.session.moments.isEmpty {
            emptyHint("Add tags and hobbies, or photos with the + button. They show on your badge.",
                      agentText: "Here are my interests:")
        }
    }

    private func eventBlock(_ p: UserProfile?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "At this event") {
                IconButton(systemImage: "pencil", label: "Edit event details") { editing = true }
            }
            fact("Looking for", p?.lookingFor)
            fact("I can help with", p?.offers)
            fact("How to find me", p?.appearance)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.blue, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }

    private var agentBlock: some View {
        Card {
            Text("Your agent").font(theme.headline)
            Text("Text it anything: who you want to meet, how a chat went, or to update your profile.")
                .font(theme.body).foregroundStyle(theme.inkSecondary)
            if let url = AppConfig.agentSMSURL(body: "Hi!") {
                Button("Text your agent") { openURL(url) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: Helpers

    private func fact(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(theme.caption.weight(.semibold)).foregroundStyle(theme.ink.opacity(0.7))
            Text(value?.nilIfBlank ?? "Not set yet")
                .font(theme.body)
                .foregroundStyle(value?.nilIfBlank == nil ? theme.inkSecondary : theme.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 18))
    }

    private func emptyHint(_ text: String, agentText: String) -> some View {
        Card(fill: theme.surface.opacity(0.85)) {
            Text(text).font(theme.body).foregroundStyle(theme.inkSecondary)
            HStack(spacing: 12) {
                Button("Add") { editing = true }.buttonStyle(SecondaryButtonStyle())
                if let url = AppConfig.agentSMSURL(body: agentText) {
                    Button("Text your agent") { openURL(url) }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private func saveMoment() {
        guard let data = pendingMoment else { return }
        let caption = momentCaption
        pendingMoment = nil
        momentCaption = ""
        Task { await env.session.addMoment(data, caption: caption) }
    }

    /// The identity card as it looks with nobody nearby.
    private func previewConfiguration(_ p: UserProfile?) -> BadgeConfiguration {
        BadgeConfiguration(
            name: p?.displayName ?? "Your name",
            company: p?.company?.nilIfBlank,
            role: p?.headline?.nilIfBlank,
            location: p?.location?.nilIfBlank,
            layout: p?.layout ?? .avatar,
            photoURL: p?.photoURL,
            avatar: p?.avatar ?? AvatarStyle(shape: nil, color: nil),
            hasProfile: p?.isMatchable ?? false,
            interests: [],
            tags: p?.badgeTags ?? [],
            moments: [],
            frontTag: nil,
            mode: .idle,
            closeness: 0,
            matchColor: nil,
            peerName: nil,
            peerAvatar: nil,
            peerSeed: 0,
            look: nil,
            presentation: .window,
            orientation: .vertical
        )
    }
}

/// "Region" control from the design. California asks before every recording.
private struct RegionPill: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme

    var body: some View {
        let california = env.session.profile?.californiaMode ?? true
        Menu {
            Picker("Region", selection: Binding(
                get: { california },
                set: { value in Task { await env.session.update(ProfilePatch(californiaMode: value)) } }
            )) {
                Text("California: ask before recording").tag(true)
                Text("Elsewhere: record automatically").tag(false)
            }
        } label: {
            HStack(spacing: 8) {
                Text("Region").font(.brand(15, .semibold)).foregroundStyle(theme.ink)
                Text(california ? "CA" : "Other")
                    .font(.brand(15, .semibold))
                    .foregroundStyle(theme.strongInk)
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(theme.yellowStrong, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(5)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 4)
        }
        .accessibilityLabel("Recording region, \(california ? "California" : "elsewhere")")
    }
}
