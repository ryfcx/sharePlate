//
//  UserAccount.swift
//  sharePlate
//
//  Local account record. Passwords are stored only as salted SHA-256 hashes.
//  When a real backend is added, identity moves server-side and this becomes a
//  cached profile.
//

import Foundation
import SwiftData

@Model
final class UserAccount {
    @Attribute(.unique) var id: String
    var displayName: String
    var email: String
    var passwordHash: String
    var salt: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        displayName: String,
        email: String,
        passwordHash: String,
        salt: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.passwordHash = passwordHash
        self.salt = salt
        self.createdAt = createdAt
    }
}
