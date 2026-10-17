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
        guard !session.deletionPending, !session.hasDeletedData else { isReady = true; return }
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
        guard !AccountDeletionStorage.preventsAutomaticSignIn else { throw AccountDeletionError.unfinished }
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
        guard session.allowsDataAccess else { return }
        session.currentUserID = authSession.user.id.uuidString
        authenticationError = nil
        isReady = true
        Task {
            await PushNotificationService.shared.uploadTokenIfNeeded()
            await HandoffLiveUpdatesService.shared.refreshSubscriptions()
        }
    }

    func deleteData(store: LocalDataStore, location: LocationManager) async throws {
        guard !session.isDeletingData else { return }
        session.isDeletingData = true
        defer { session.isDeletingData = false }
        let request = try await AccountDeletionService.prepare()
        session.deletionPending = true
        await ListingCatalogSyncService.shared.stopAndWait()
        await HandoffLiveUpdatesService.shared.stopAndWait()
        await PushNotificationService.shared.clearLocalNotifications()
        location.resetAfterDataDeletion()
        try await AccountDeletionService.execute(request)
        try store.erasePersonalData()
        session.resetPersonalIdentity()
        session.hasDeletedData = true
        session.deletionPending = false
        try? AccountDeletionStorage.clear()
        try? await SupabaseManager.client.auth.signOut(scope: .local)
        await PushNotificationService.shared.clearLocalNotifications()
    }

    func startFresh() async throws {
        guard session.hasDeletedData, !session.deletionPending else { throw AccountDeletionError.unfinished }
        try AccountDeletionStorage.clear()
        try? await SupabaseManager.client.auth.signOut(scope: .local)
        let fresh: Session
        do { fresh = try await SupabaseManager.client.auth.signInAnonymously() }
        catch { throw AccountDeletionError.startFailed }
        session.hasDeletedData = false
        setCurrent(fresh)
        isReady = true
    }
}
