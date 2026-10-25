import SwiftUI

/// Fill in your profile by hand. Lists are comma separated.
struct ProfileEditView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var headline = ""
    @State private var company = ""
    @State private var location = ""
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
                        .textContentType(.givenName)
                    TextField("Role, e.g. Brand marketer", text: $headline)
                        .textContentType(.jobTitle)
                    TextField("Company or school", text: $company)
                        .textContentType(.organizationName)
                    TextField("City, e.g. Vancouver, BC", text: $location)
                        .textContentType(.addressCity)
                }
                Section {
                    TextField("e.g. Student, Product designer, Startup founder", text: $tags)
                    TextField("Hobbies, e.g. Climbing, Film photos", text: $hobbies)
                } header: {
                    Text("Interests")
                } footer: {
                    Text("Comma separated. These are conversation starters on your badge; the one a nearby match cares about moves to the front.")
                }
                Section("At this event") {
                    TextField("Who you want to meet", text: $lookingFor, axis: .vertical)
                    TextField("What you can help with", text: $offers, axis: .vertical)
                }
                Section {
                    TextField("How to find you, e.g. red cap", text: $appearance)
                } footer: {
                    Text("Your agent uses this to tell matches who to look for.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let p = env.session.profile else { return }
        name = p.name ?? ""
        headline = p.headline ?? ""
        company = p.company ?? ""
        location = p.location ?? ""
        tags = (p.tags ?? []).joined(separator: ", ")
        lookingFor = p.lookingFor ?? ""
        offers = p.offers ?? ""
        hobbies = (p.hobbies ?? []).joined(separator: ", ")
        appearance = p.appearance ?? ""
    }

    /// Sends every field, so clearing one clears it on the server too.
    private func save() async {
        await env.session.update(ProfilePatch(
            name: name.trimmed,
            headline: headline.trimmed,
            company: company.trimmed,
            location: location.trimmed,
            tags: Self.list(tags),
            lookingFor: lookingFor.trimmed,
            offers: offers.trimmed,
            hobbies: Self.list(hobbies),
            appearance: appearance.trimmed
        ))
        dismiss()
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
