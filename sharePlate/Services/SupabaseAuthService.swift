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
    private let client = SupabaseManager.client

    private(set) var isReady = false

    init(session: SessionContext) {
        self.session = session
        Task { await restoreOrCreateSession() }
    }

    private func restoreOrCreateSession() async {
        if var authSession = client.auth.currentSession {
            if authSession.isExpired {
                do {
                    authSession = try await client.auth.refreshSession()
                } catch {
                    await signInAnonymously()
                    return
                }
            }
            setCurrent(authSession)
            return
        }
        await signInAnonymously()
    }

    private func signInAnonymously() async {
        do {
            let authSession = try await client.auth.signInAnonymously()
            setCurrent(authSession)
        } catch {
            // Leave currentUserID nil; posting/reserving will surface a clear
            // error until connectivity allows the anonymous session to succeed.
            isReady = true
        }
    }

    private func setCurrent(_ authSession: Session) {
        session.currentUserID = authSession.user.id.uuidString
        isReady = true
        Task {
            await PushNotificationService.shared.uploadTokenIfNeeded()
            await HandoffLiveUpdatesService.shared.refreshSubscriptions()
        }
    }
}
