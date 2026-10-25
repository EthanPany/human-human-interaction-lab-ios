import SwiftUI

/// Sign up or sign in with a phone number. Name and password are optional.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var phone = ""
    @State private var name = ""
    @State private var password = ""
    @State private var busy = false
    @FocusState private var focused: Field?

    private enum Field { case phone, name, password }

    var body: some View {
        ZStack {
            FlowingBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        AvatarView(shape: .blob, color: theme.red, expression: busy ? .excited : .curious, seed: 3)
                            .frame(width: 130, height: 130)
                        Spacer()
                    }
                    .padding(.top, 36)

                    Card {
                        Text("Meet the right people").font(.brand(34, .semibold)).foregroundStyle(theme.strongInk)
                        Text("Your phone becomes a live badge. Your agent texts you who to meet and remembers them for you.")
                            .font(theme.body)
                            .foregroundStyle(theme.inkSecondary)

                        field("Phone number", text: $phone, keyboard: .phonePad, content: .telephoneNumber)
                            .focused($focused, equals: .phone)
                        field("Name (optional)", text: $name, keyboard: .default, content: .givenName)
                            .focused($focused, equals: .name)
                        SecureField("Password (optional)", text: $password,
                                    prompt: Text("Password (optional)").foregroundStyle(theme.inkSecondary))
                            .textContentType(.password)
                            .focused($focused, equals: .password)
                            .font(theme.body)
                            .padding(14)
                            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))

                        if let error = env.session.lastError {
                            Text(error).font(theme.caption).foregroundStyle(theme.red)
                        }

                        Button {
                            submit()
                        } label: {
                            if busy { ProgressView() } else { Text("Continue") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(phone.filter(\.isNumber).count < 10 || busy)
                        .padding(.top, 4)
                    }
                }
                .padding(theme.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focused = .phone }
    }

    private func submit() {
        busy = true
        focused = nil
        Task {
            await env.session.signIn(phone: phone, name: name, password: password)
            busy = false
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType, content: UITextContentType) -> some View {
        TextField(title, text: text, prompt: Text(title).foregroundStyle(theme.inkSecondary))
            .keyboardType(keyboard)
            .textContentType(content)
            .font(theme.body)
            .foregroundStyle(theme.strongInk)
            .padding(14)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
    }
}
