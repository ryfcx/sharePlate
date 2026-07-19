//
//  AuthService.swift
//  sharePlate
//
//  Authentication abstraction. `LocalAuthService` stores accounts on-device in
//  SwiftData; a future `RemoteAuthService` can implement the same surface
//  against a backend without changing the views.
//

import Foundation
import SwiftData

enum AuthError: LocalizedError {
    case missingFields
    case invalidEmail
    case weakPassword
    case emailInUse
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .missingFields: return "Please fill in all fields."
        case .invalidEmail: return "Enter a valid email address."
        case .weakPassword: return "Password must be at least 6 characters."
        case .emailInUse: return "An account with that email already exists."
        case .invalidCredentials: return "Incorrect email or password."
        }
    }
}

@MainActor
protocol AuthService {
    var currentUser: UserAccount? { get }
    var isSignedIn: Bool { get }
    @discardableResult
    func signUp(name: String, email: String, password: String) async throws -> UserAccount
    @discardableResult
    func signIn(email: String, password: String) async throws -> UserAccount
    func signOut()
}

@MainActor
@Observable
final class LocalAuthService: AuthService {
    private let context: ModelContext
    private let session: SessionContext
    private let currentUserKey = "sharePlate.currentUserID"

    private(set) var currentUser: UserAccount?

    init(context: ModelContext, session: SessionContext) {
        self.context = context
        self.session = session
        restoreSession()
    }

    var isSignedIn: Bool { currentUser != nil }

    func restoreSession() {
        guard let id = UserDefaults.standard.string(forKey: currentUserKey),
              let user = user(withID: id) else { return }
        setCurrent(user)
    }

    @discardableResult
    func signUp(name: String, email: String, password: String) async throws -> UserAccount {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = normalized(email)

        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else { throw AuthError.missingFields }
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        guard password.count >= 6 else { throw AuthError.weakPassword }
        guard user(withEmail: email) == nil else { throw AuthError.emailInUse }

        let salt = PasswordHasher.makeSalt()
        let account = UserAccount(
            displayName: name,
            email: email,
            passwordHash: PasswordHasher.hash(password, salt: salt),
            salt: salt
        )
        context.insert(account)
        try? context.save()
        setCurrent(account)
        return account
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> UserAccount {
        let email = normalized(email)
        guard !email.isEmpty, !password.isEmpty else { throw AuthError.missingFields }
        guard let account = user(withEmail: email),
              PasswordHasher.verify(password, salt: account.salt, expectedHash: account.passwordHash) else {
            throw AuthError.invalidCredentials
        }
        setCurrent(account)
        return account
    }

    func signOut() {
        currentUser = nil
        session.currentUserID = nil
        UserDefaults.standard.removeObject(forKey: currentUserKey)
    }

    // MARK: - Helpers

    private func setCurrent(_ user: UserAccount) {
        currentUser = user
        session.currentUserID = user.id
        UserDefaults.standard.set(user.id, forKey: currentUserKey)
    }

    private func user(withID id: String) -> UserAccount? {
        let descriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func user(withEmail email: String) -> UserAccount? {
        let descriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.email == email })
        return try? context.fetch(descriptor).first
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }
}
