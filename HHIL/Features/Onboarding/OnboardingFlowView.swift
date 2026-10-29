import SwiftUI

/// What follows sign up: pick your avatar, then choose how to fill your profile.
/// Step 1 (the account) is already done when this shows.
struct OnboardingFlowView: View {
    enum Step: Int, Comparable {
        case avatar = 1, setup = 2
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    var start: Step
    var onDone: () -> Void

    @Environment(\.theme) private var theme
    @State private var step: Step?

    var body: some View {
        let current = step ?? start
        VStack(spacing: 0) {
            ProgressDots(count: 3, current: current.rawValue)
                .padding(.top, 20)
                .padding(.bottom, 4)
            ZStack {
                switch current {
                case .avatar:
                    AvatarSetupStep { go(to: .setup) }
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                case .setup:
                    SetupChoiceView(onDone: onDone)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
    }

    private func go(to next: Step) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = next }
    }
}

/// "Step n of count": the current step is a wide pill, done steps are filled.
struct ProgressDots: View {
    var count: Int
    /// Zero based.
    var current: Int
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? theme.strongInk : theme.strongInk.opacity(0.18))
                    .frame(width: i == current ? 26 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Pick a shape and a color for the avatar that lives on your badge.
private struct AvatarSetupStep: View {
    var onNext: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var shape: AvatarShapeKind = .blob
    @State private var colorHex: String = Theme.playful.avatarSwatches[0]
    @State private var customColor: Color = Theme.playful.red
    @State private var expression: AvatarExpression = .happy
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make your avatar").font(theme.title).foregroundStyle(theme.strongInk)
                    Text("It lives on your badge and reacts when someone you should meet is near. You can change it anytime.")
                        .font(theme.body)
                        .foregroundStyle(theme.inkSecondary)
                }
                AvatarPreview(shape: shape, colorHex: colorHex, expression: $expression, size: 160)
                AvatarShapeGrid(selection: shape, colorHex: colorHex) { kind in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { shape = kind }
                    bounce()
                }
                AvatarColorRow(selection: colorHex, customColor: $customColor) { hex in
                    colorHex = hex
                    bounce()
                }
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Continue") { finish(save: true) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving)
                Button("Skip for now") { finish(save: false) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(theme.background)
        }
        .onAppear {
            // Start from whatever the account has (the default for a new one)
            if let p = env.session.profile {
                shape = p.avatar.shape
                colorHex = p.avatar.colorHex
                customColor = p.avatar.color
            }
        }
    }

    /// A happy little reaction to every pick.
    private func bounce() {
        expression = .excited
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            expression = .happy
        }
    }

    private func finish(save: Bool) {
        saving = true
        Task {
            await env.session.finishAvatarSetup(shape: save ? shape.rawValue : nil,
                                                color: save ? colorHex : nil)
            onNext()
        }
    }
}
