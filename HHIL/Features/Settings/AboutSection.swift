import SwiftUI

/// Settings > About: version, the project links and who made it.
struct AboutSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme

    /// EDIT ME: Ethan's homepage. No personal site was found in the repos (README,
    /// Devpost text, docs, git config), so this is his GitHub profile for now.
    static let developerHomepage = URL(string: "https://github.com/EthanPany")!
    static let devpost = URL(string: "https://devpost.com/software/human-human-interaction-lab")!
    static let github = URL(string: "https://github.com/EthanPany/human-human-interaction-lab")!

    struct Credit: Identifiable {
        let name: String
        let school: String
        let role: String?
        var id: String { name }
    }

    static let team: [Credit] = [
        Credit(name: "Ethan Pan", school: "UC Berkeley and UW Madison", role: "Tech lead"),
        Credit(name: "Paul Jiang", school: "UC Irvine", role: nil),
        Credit(name: "Jiayi Tang", school: "UC Berkeley", role: nil),
        Credit(name: "Kenny Nguyen", school: "SFU", role: "Designer"),
    ]

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Section {
            LabeledContent("Version", value: Self.version)
            link("Devpost", systemImage: "trophy", url: Self.devpost)
            link("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: Self.github)
        } header: {
            Text("About")
        } footer: {
            Text("Human Human Interaction Lab: your phone, worn on a lanyard, becomes a live name badge. Made at Cal Hacks 13.0.")
        }

        Section("Team") {
            ForEach(Self.team) { person in
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(theme.headline).foregroundStyle(theme.strongInk)
                    Text([person.role, person.school].compactMap { $0 }.joined(separator: ", "))
                        .font(theme.caption).foregroundStyle(theme.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }

        Section {
            LabeledContent("Developer", value: "Ethan Pan")
            link("Ethan's homepage", systemImage: "house", url: Self.developerHomepage)
        } header: {
            Text("Developer")
        }
    }

    private func link(_ title: String, systemImage: String, url: URL) -> some View {
        Button {
            Feedback.shared.play(.buttonPress)
            openURL(url)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right").font(theme.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }
}
