//
//  SupabaseAuthService.swift
//  sharePlate
//
//  No login screen: establishes a silent anonymous Supabase auth session on
//  launch so Postgres RLS policies still have a real auth.uid() to key off
//  of, without ever showing sign-up/sign-in UI. Restores the existing
//  session (anonymous or not) if one is already on-device.
//

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
            // Browsing remains available while offline or while anonymous auth
            // is unavailable. Mutating actions retry authentication on demand.
            isReady = true
        }
    }

    /// Returns a valid Supabase session, creating an anonymous user when this
    /// device has never authenticated. Called again by write operations so one
    /// failed launch attempt does not leave the app unauthenticated forever.
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
