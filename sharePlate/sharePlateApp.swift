//
//  sharePlateApp.swift
//  sharePlate
//
//  Created by Ryan Gupta on 5/31/26.
//

import SwiftUI
import SwiftData

@main
struct sharePlateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    private let session: SessionContext
    @State private var location = LocationManager()
    @State private var store: LocalDataStore
    @State private var auth: SupabaseAuthService

    init() {
        FontRegistrar.registerBundledFonts()
        AppAppearance.configure()

        let container: ModelContainer
        do {
            container = try ModelContainerFactory.make()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let session = SessionContext()
        self.container = container
        self.session = session
        _store = State(initialValue: LocalDataStore(context: container.mainContext, session: session))
        _auth = State(initialValue: SupabaseAuthService(session: session))

        PushNotificationService.shared.configure(session: session)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(location)
                .environment(session)
                .environment(store)
                .environment(auth)
        }
        .modelContainer(container)
    }
}
