//
//  AppRootView.swift
//  sharePlate
//
//  Top-level gate: requires sign-in before showing the app.
//

import SwiftUI

struct AppRootView: View {
    @Environment(SupabaseAuthService.self) private var auth

    var body: some View {
        if auth.isSignedIn {
            RootTabView()
        } else {
            AuthView()
        }
    }
}
