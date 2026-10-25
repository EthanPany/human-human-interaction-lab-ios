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

                        // Order matters for iOS autofill: the field right above the
                        // password is treated as the account name, so that's the phone.
                        LabeledField(title: "Name", hint: "e.g. Ethan Pan", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focused, equals: .name)
                            .onSubmit { focused = .phone }
                        LabeledField(title: "Phone number", hint: "(415) 555 0123", text: $phone,
                                     footnote: phoneNote)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focused, equals: .phone)
                        LabeledField(title: "Password", hint: "Optional, to sign in on another phone",
                                     text: $password, secure: true)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focused, equals: .password)
                            .onSubmit { if canSubmit { submit() } }

                        if let error = env.session.lastError {
                            Text(error).font(theme.caption).foregroundStyle(theme.red)
                        }

                        Button {
                            submit()
                        } label: {
                            if busy { ProgressView() } else { Text("Continue") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSubmit)
                        .padding(.top, 4)
                    }
                }
                .padding(theme.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focused = .name }
        .toolbar {
            // The phone pad has no Return key
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if focused == .phone {
                    Button("Next") { focused = .password }.fontWeight(.semibold)
                }
            }
        }
    }

    private func submit() {
        busy = true
        focused = nil
        Task {
            await env.session.signIn(phone: normalizedPhone ?? phone, name: name, password: password)
            busy = false
        }
    }

    private var normalizedPhone: String? { PhoneNumber.normalize(phone) }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && normalizedPhone != nil && !busy
    }

    /// Confirms what we understood, whatever format autofill used.
    private var phoneNote: String {
        if let e164 = normalizedPhone { return "Your agent texts \(PhoneNumber.display(e164))" }
        if phone.isEmpty { return "Your agent texts this number." }
        return "Add the country code if it's not a US number."
    }
}
