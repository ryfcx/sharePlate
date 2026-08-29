//
//  PushNotificationService.swift
//  sharePlate
//
//  Registers for APNs and uploads tokens to Supabase. Delivery is handled by the
//  `send-handoff-push` Edge Function — see `supabase/README_PUSH.md`.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()

    private(set) var deviceToken: String?
    private var session: SessionContext?

    private override init() {
        super.init()
    }

    func configure(session: SessionContext) {
        self.session = session
        UNUserNotificationCenter.current().delegate = self
    }

    /// Requests local-notification permission (needed for nearby-alert local
    /// notifications regardless of push) and, only when push is enabled,
    /// registers for APNs remote notifications too.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted, PushNotificationConfiguration.isEnabled else { return }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            // User declined or system error — in-app Realtime still works.
        }
    }

    func setDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = token
        Task { await uploadTokenIfNeeded() }
    }

    func uploadTokenIfNeeded() async {
        guard PushNotificationConfiguration.isEnabled,
              let token = deviceToken,
              let userIDString = session?.currentUserID,
              let userID = UUID(uuidString: userIDString) else { return }
        try? await SupabaseDeviceTokenService.upsert(userID: userID, token: token)
    }

    func clearTokenOnSignOut() async {
        guard let token = deviceToken,
              let userIDString = session?.currentUserID,
              let userID = UUID(uuidString: userIDString) else { return }
        await SupabaseDeviceTokenService.remove(userID: userID, token: token)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            LocalNotice.postFromPush(userInfo: response.notification.request.content.userInfo)
            if let listingID = response.notification.request.content.userInfo["listing_id"] as? String {
                LocalNotice.shared.openHandoff(listingRemoteID: listingID)
            }
        }
    }
}
