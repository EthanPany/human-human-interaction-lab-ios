import SwiftUI

/// Signed out: onboarding. Signed in: the tabs. Also reacts to the iPhone Duo hinge.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.session.isSignedIn {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .onChange(of: env.session.userId, initial: true) { _, id in
            env.userDidChange(id)
        }
        .onFoldChange(perform: handleFold)
        .onAppear { Feedback.shared.prepare() }
    }

    /// iPhone Duo: closing shows the worn badge on the outer display; opening
    /// goes straight to the person you're with (or met last) on the inner display.
    private func handleFold(_ state: FoldState) {
        switch state {
        case .closed:
            env.badge.wear()
        case .open:
            env.badge.takeOff()
            env.router.showPerson(env.badge.state.peerId ?? env.currentPersonId)
        case .partiallyOpen:
            break
        }
    }
}
