// session context
import Foundation
import SwiftUI

@Observable
final class SessionContext {
    // backup id used before login is ready
    private(set) var deviceID: String
    private let defaults: UserDefaults
    var isDeletingData = false
    var deletionPending: Bool {
        didSet { defaults.set(deletionPending, forKey: AccountDeletionStorage.pendingKey) }
    }
    var hasDeletedData: Bool {
        didSet { defaults.set(hasDeletedData, forKey: AccountDeletionStorage.deletedKey) }
    }
    var allowsDataAccess: Bool { !isDeletingData && !deletionPending && !hasDeletedData }

    // filled in once quiet login finishes
    var currentUserID: String?

    // who posts belong to, login id first then phone id
    var identity: String { currentUserID ?? deviceID }

    private let displayNameKey = "sharePlate.displayName"

    // name from settings, neighbor to start
    var displayName: String {
        didSet { defaults.set(displayName, forKey: displayNameKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let deleted = defaults.bool(forKey: AccountDeletionStorage.deletedKey)
        let recovered = !deleted && defaults === UserDefaults.standard && (try? AccountDeletionStorage.load()) != nil
        deletionPending = !deleted && (defaults.bool(forKey: AccountDeletionStorage.pendingKey) || recovered)
        hasDeletedData = deleted
        if recovered {
            defaults.set(true, forKey: AccountDeletionStorage.pendingKey)
        }
        if deleted { defaults.set(false, forKey: AccountDeletionStorage.pendingKey) }
        let key = "sharePlate.deviceID"
        if let existing = defaults.string(forKey: key) {
            deviceID = existing
        } else {
            let new = UUID().uuidString
            defaults.set(new, forKey: key)
            deviceID = new
        }
        displayName = defaults.string(forKey: displayNameKey) ?? String(localized: "Neighbor")
    }

    func resetPersonalIdentity() {
        currentUserID = nil
        displayName = String(localized: "Neighbor")
        deviceID = UUID().uuidString
        defaults.set(deviceID, forKey: "sharePlate.deviceID")
    }

    // matches ids without caring about caps
    func matches(_ userID: String?) -> Bool {
        guard let userID else { return false }
        return identity.caseInsensitiveCompare(userID) == .orderedSame
    }
}
