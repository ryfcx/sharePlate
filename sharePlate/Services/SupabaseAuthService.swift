// supabase auth service
import Foundation
import Supabase

@MainActor
@Observable
final class SupabaseAuthService {
    private let session: SessionContext

    private(set) var isReady = false
    private(set) var authenticationError: String?

    init(session: SessionContext) {
        self.session = session
        Task { await restoreOrCreateSession() }
    }

    private func restoreOrCreateSession() async {
        do {
            let authSession = try await Self.ensureSession()
            setCurrent(authSession)
        } catch {
            authenticationError = error.localizedDescription
// browsing still works offline, writes retry later
            isReady = true
        }
    }

    // gets a login, making a quiet new one if needed
    static func ensureSession() async throws -> Session {
        let client = SupabaseManager.client
        if var authSession = client.auth.currentSession {
            if authSession.isExpired {
                do {
                    authSession = try await client.auth.refreshSession()
                } catch {
                    return try await client.auth.signInAnonymously()
                }
            }
            return authSession
        }
        return try await client.auth.signInAnonymously()
    }

    private func setCurrent(_ authSession: Session) {
        session.currentUserID = authSession.user.id.uuidString
        authenticationError = nil
        isReady = true
        Task {
            await PushNotificationService.shared.uploadTokenIfNeeded()
            await HandoffLiveUpdatesService.shared.refreshSubscriptions()
        }
    }
}
