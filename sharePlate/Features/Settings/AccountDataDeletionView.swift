import SwiftUI

struct AccountDataDeletionView: View {
    @Environment(SessionContext.self) private var session
    @Environment(SupabaseAuthService.self) private var auth
    @Environment(LocalDataStore.self) private var store
    @Environment(LocationManager.self) private var location
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(session.hasDeletedData ? String(localized: "Your data has been deleted") : String(localized: "Deleting your data"))
                    .font(AppFont.title)
                Text(session.hasDeletedData
                    ? String(localized: "Your anonymous account and its data have been removed. You can close the app, or start again with a new anonymous account.")
                    : String(localized: "Your deletion request is saved securely. If the connection drops, tap Retry deletion to finish. You cannot use your old account while deletion is pending."))
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.mutedText)
                if session.isDeletingData || isWorking {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 48)
                } else {
                    Button { Task { await continueAction() } } label: {
                        Text(session.hasDeletedData ? String(localized: "Start fresh") : String(localized: "Retry deletion"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if let errorMessage {
                    Text(errorMessage).font(AppFont.body).foregroundStyle(Theme.Palette.urgentRed)
                }
                Link("Support", destination: AppLinks.support)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.primaryGreen)
                    .frame(minHeight: 44)
            }
            .foregroundStyle(Theme.Palette.primaryText)
            .padding(Theme.Spacing.lg)
        }
        .screenBackground()
    }

    private func continueAction() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if session.hasDeletedData { try await auth.startFresh() }
            else { try await auth.deleteData(store: store, location: location) }
        } catch let error as AccountDeletionError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = (session.hasDeletedData ? AccountDeletionError.startFailed : .unfinished).localizedDescription
        }
    }
}
