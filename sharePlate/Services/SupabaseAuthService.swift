//
//  SupabaseAuthService.swift
//  sharePlate
//

import Foundation
import Supabase

@MainActor
@Observable
final class SupabaseAuthService: AuthService {
    private let session: SessionContext
    private let client = SupabaseManager.client

    private(set) var currentUser: UserAccount?

    init(session: SessionContext) {
        self.session = session
        Task { await restoreSession() }
    }

    var isSignedIn: Bool { currentUser != nil }

    func restoreSession() async {
        guard var authSession = client.auth.currentSession else { return }

        if authSession.isExpired {
            do {
                authSession = try await client.auth.refreshSession()
            } catch {
                clearLocalSession()
                return
            }
        }

        guard !authSession.isExpired else {
            clearLocalSession()
            return
        }

        setCurrent(user: authSession.user)
    }

    @discardableResult
    func signUp(name: String, email: String, password: String) async throws -> UserAccount {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = normalized(email)

        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else { throw AuthError.missingFields }
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        guard password.count >= 6 else { throw AuthError.weakPassword }

        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(name)]
        )

        if response.session != nil {
            return setCurrent(user: response.user, fallbackName: name, fallbackEmail: email)
        }

        // Email confirmation off should return a session; if not, sign in so inserts carry a JWT.
        let session = try await client.auth.signIn(email: email, password: password)
        return setCurrent(user: session.user, fallbackName: name, fallbackEmail: email)
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> UserAccount {
        let email = normalized(email)
        guard !email.isEmpty, !password.isEmpty else { throw AuthError.missingFields }

        let session = try await client.auth.signIn(email: email, password: password)
        let account = setCurrent(user: session.user)
        return account
    }

    func signOut() {
        Task {
            await PushNotificationService.shared.clearTokenOnSignOut()
            HandoffLiveUpdatesService.shared.stop()
            ListingCatalogSyncService.shared.stop()
        }
        currentUser = nil
        session.currentUserID = nil
        Task { try? await client.auth.signOut() }
    }

    // MARK: - Helpers

    private func clearLocalSession() {
        currentUser = nil
        session.currentUserID = nil
    }

    @discardableResult
    private func setCurrent(user: User, fallbackName: String? = nil, fallbackEmail: String? = nil) -> UserAccount {
        let metadata = user.userMetadata
        let displayName = metadata["display_name"]?.stringValue
            ?? fallbackName
            ?? user.email?.split(separator: "@").first.map(String.init)
            ?? "Neighbor"
        let email = user.email ?? fallbackEmail ?? ""

        let account = UserAccount(
            id: user.id.uuidString,
            displayName: displayName,
            email: email,
            passwordHash: "",
            salt: ""
        )
        currentUser = account
        session.currentUserID = account.id
        Task {
            await PushNotificationService.shared.uploadTokenIfNeeded()
            await HandoffLiveUpdatesService.shared.refreshSubscriptions()
        }
        return account
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }
}

private extension AnyJSON {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}
