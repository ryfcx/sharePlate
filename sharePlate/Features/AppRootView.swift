//
//  AppRootView.swift
//  sharePlate
//
//  No login gate — briefly waits for the silent anonymous auth session
//  (needed for RLS) before showing the app, rather than requiring sign-in.
//

import SwiftUI

struct AppRootView: View {
    @Environment(SupabaseAuthService.self) private var auth

    var body: some View {
        if auth.isReady {
            RootTabView()
        } else {
            ProgressView()
                .screenBackground()
        }
    }
}
