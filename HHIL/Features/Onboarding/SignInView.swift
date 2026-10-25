import SwiftUI

/// Sign up or sign in with a phone number. Name and password are optional.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var phone = ""
    @State private var name = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 40)
            Text("Meet the right people").font(theme.largeTitle)
            Text("Your phone becomes your badge. Your agent texts you who to meet and remembers them for you.")
                .foregroundStyle(theme.inkSecondary)

            field("Phone number", text: $phone, keyboard: .phonePad, content: .telephoneNumber)
            field("Name (optional)", text: $name, keyboard: .default, content: .givenName)
            SecureField("Password (optional)", text: $password)
                .padding(14)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))

            if let error = env.session.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Spacer()

            Button {
                busy = true
                Task {
                    await env.session.signIn(phone: phone, name: name, password: password)
                    busy = false
                }
            } label: {
                Group {
                    if busy { ProgressView() } else { Text("Continue").font(.headline) }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.ink)
            .disabled(phone.filter(\.isNumber).count < 10 || busy)
        }
        .padding(24)
        .background(theme.background)
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType, content: UITextContentType) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .textContentType(content)
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
