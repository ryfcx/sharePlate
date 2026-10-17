//
// approotview.swift
// shareplate
//
// no login gate shows splash while auth finishes
// silent anonymous session is needed for access
//

import SwiftUI

struct AppRootView: View {
    @Environment(SupabaseAuthService.self) private var auth
    @Environment(SessionContext.self) private var session
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if session.hasDeletedData || session.deletionPending {
                AccountDataDeletionView()
            } else if auth.isReady, !showSplash {
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
