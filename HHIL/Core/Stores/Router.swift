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
    var peoplePath: [String] = [] // person ids

    /// Jump to a person's detail in People (used when an iPhone Duo opens).
    func showPerson(_ id: String?) {
        tab = .people
        if let id { peoplePath = [id] } else { peoplePath = [] }
    }
}
