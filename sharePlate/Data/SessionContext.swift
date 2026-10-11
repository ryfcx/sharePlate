// session context
import Foundation
import SwiftUI

@Observable
final class SessionContext {
    // backup id used before login is ready
    let deviceID: String

    // filled in once quiet login finishes
    var currentUserID: String?

    // who posts belong to, login id first then phone id
    var identity: String { currentUserID ?? deviceID }

    private let displayNameKey = "sharePlate.displayName"

    // name from settings, neighbor to start
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: displayNameKey) }
    }

    init() {
        let key = "sharePlate.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceID = existing
        } else {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: key)
            deviceID = new
        }
        displayName = UserDefaults.standard.string(forKey: displayNameKey) ?? String(localized: "Neighbor")
    }

    // matches ids without caring about caps
    func matches(_ userID: String?) -> Bool {
        guard let userID else { return false }
        return identity.caseInsensitiveCompare(userID) == .orderedSame
    }
}
