import SwiftUI

/// iPhone Duo fold state, simplified for app logic.
enum FoldState {
    case closed, partiallyOpen, open
}

extension View {
    /// Calls `action` when an iPhone Duo is closed, partially opened or opened.
    /// Does nothing on phones without a hinge. Use for behavior, not layout:
    /// layouts follow size classes.
    func onFoldChange(perform action: @escaping (FoldState) -> Void) -> some View {
        modifier(FoldChangeModifier(action: action))
    }
}

/// The only file that touches the iOS 27 hinge API, so SDK differences stay contained.
private struct FoldChangeModifier: ViewModifier {
    let action: (FoldState) -> Void

    func body(content: Content) -> some View {
        // The hinge API ships in the iOS 27 SDK (Xcode 27, Swift 6.3). Older
        // toolchains, like CI on Xcode 26, build without it.
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) {
            content.onHingeChange { _, context in
                guard let hinge = context.hinge else { return } // no hinge: normal iPhone
                switch hinge.status {
                case .closed: action(.closed)
                case .partiallyOpen: action(.partiallyOpen)
                case .fullyOpen: action(.open)
                @unknown default: break
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
