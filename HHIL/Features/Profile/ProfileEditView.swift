import SwiftUI

/// Fill in your profile by hand. Lists are comma separated.
struct ProfileEditView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var headline = ""
    @State private var tags = ""
    @State private var lookingFor = ""
    @State private var offers = ""
    @State private var hobbies = ""
    @State private var appearance = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $name)
                    TextField("Headline, e.g. CS student building AI tools", text: $headline)
                }
                Section {
                    TextField("e.g. Student, Product designer, Startup founder", text: $tags)
                } header: {
                    Text("Badge tags")
                } footer: {
                    Text("Short conversation starters shown on your badge. The one a nearby match cares about moves to the front.")
                }
                Section("At this event") {
                    TextField("Who you want to meet", text: $lookingFor, axis: .vertical)
                    TextField("What you can help with", text: $offers, axis: .vertical)
                }
                Section {
                    TextField("Hobbies, comma separated", text: $hobbies)
                    TextField("How to find you, e.g. red cap", text: $appearance)
                } footer: {
                    Text("Your agent uses this to tell matches who to look for.")
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let p = env.session.profile else { return }
        name = p.name ?? ""
        headline = p.headline ?? ""
        tags = (p.tags ?? []).joined(separator: ", ")
        lookingFor = p.lookingFor ?? ""
        offers = p.offers ?? ""
        hobbies = (p.hobbies ?? []).joined(separator: ", ")
        appearance = p.appearance ?? ""
    }

    private func save() async {
        await env.session.update(ProfilePatch(
            name: name.nilIfBlank,
            headline: headline.nilIfBlank,
            tags: Self.list(tags),
            lookingFor: lookingFor.nilIfBlank,
            offers: offers.nilIfBlank,
            hobbies: Self.list(hobbies),
            appearance: appearance.nilIfBlank
        ))
        dismiss()
    }

    private static func list(_ text: String) -> [String]? {
        let items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }
}
