//
//  AppRootView.swift
//  sharePlate
//
//  No login gate — shows the branded splash while the silent anonymous
//  auth session (needed for RLS) finishes, rather than requiring sign-in.
//

import SwiftUI

struct AppRootView: View {
    @Environment(SupabaseAuthService.self) private var auth
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if auth.isReady, !showSplash {
                RootTabView()
            } else {
                SplashView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .task {
            try? await Task.sleep(for: .milliseconds(1200))
            while !auth.isReady {
                try? await Task.sleep(for: .milliseconds(50))
            }
            showSplash = false
        }
    }
}
