import Foundation
import Observation

enum AppTab: Hashable {
    case badge, people, profile
}

/// App navigation state, so non view code (hinge, notifications) can navigate.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .badge
    /// The person open in People. Wide screens show them beside the list;
    /// on a phone (or a folded Duo) setting it pushes their page.
    var selectedPersonId: String?

    /// Jump to a person's detail in People (used when an iPhone Duo opens).
    func showPerson(_ id: String?) {
        tab = .people
        selectedPersonId = id
    }
}
