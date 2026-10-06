//
//  SettingsView.swift
//  sharePlate
//

import SwiftUI
import CoreLocation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionContext.self) private var session
    @Environment(LocalDataStore.self) private var store
    @Environment(LocationManager.self) private var location
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue

    @State private var name = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var showClaimPicker = false
    @State private var showMyPantry = false

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    nameSection
                    locationSection
                    pantrySection
                    languageSection
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        commitName()
                        dismiss()
                    }
                }
            }
            .onAppear { name = session.displayName }
            .onDisappear { commitName() }
            .sheet(isPresented: $showClaimPicker) {
                PantryClaimPickerView()
            }
            .sheet(isPresented: $showMyPantry) {
                if let claim = store.myPantryClaim() {
                    MyPantryView(claim: claim)
                }
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("Nearby Alerts", systemImage: "bell.badge")
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            if location.isAuthorizedAlways {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.primaryGreen)
                    Text("Always Allow is on — you can get alerts even when the app is closed.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            } else if location.canRequestAlways {
                Button {
                    location.requestAlwaysAuthorization()
                } label: {
                    Text("Turn on Always Allow")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.lg)
                        .cardStyle(padding: 0)
                }
                .buttonStyle(.plain)

                Text("Lets SharePlate notify you when a pantry opens or new food is posted nearby, even when the app isn't open.")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Enable Location in Settings")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.lg)
                        .cardStyle(padding: 0)
                }
                .buttonStyle(.plain)
            } else {
                Text("Nearby alerts need location access — allow it when prompted on the map.")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }

    private var pantrySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("Pantry", systemImage: "building.2")
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            if let claim = store.myPantryClaim() {
                Button {
                    showMyPantry = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(claim.pantryName)
                                .font(AppFont.body)
                                .foregroundStyle(Theme.Palette.primaryText)
                                .lineLimit(2)
                            Text(claim.isTemporarilyClosed ? "Temporarily closed" : "Managing")
                                .font(AppFont.caption)
                                .foregroundStyle(claim.isTemporarilyClosed ? Theme.Palette.urgentRed : Theme.Palette.mutedText)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    .padding(Theme.Spacing.lg)
                    .cardStyle(padding: 0)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showClaimPicker = true
                } label: {
                    Text("I manage a pantry")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.lg)
                        .cardStyle(padding: 0)
                }
                .buttonStyle(.plain)

                Text("Claim your pantry from the directory to post surplus food and mark it temporarily closed.")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("Your name", systemImage: "person.fill")
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            TextField("Name", text: $name, prompt: Text("Neighbor"))
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($nameFieldFocused)
                .submitLabel(.done)
                .onSubmit { commitName() }
                .padding(12)
                .background(Theme.Palette.cardBackground)
                .boxBorder()

            Text("Shown to neighbors when you post or reserve food.")
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.displayName = trimmed.isEmpty ? String(localized: "Neighbor") : trimmed
        name = session.displayName
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("Language", systemImage: "globe")
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        appLanguageRaw = language.rawValue
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .font(AppFont.body)
                                .foregroundStyle(Theme.Palette.primaryText)
                            Spacer(minLength: Theme.Spacing.sm)
                            if language == selectedLanguage {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.primaryGreen)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if language != AppLanguage.allCases.last {
                        Rectangle()
                            .fill(Theme.Palette.hairline)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .cardStyle(padding: 0)

            Text("Changes apply immediately across the app.")
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }
}
