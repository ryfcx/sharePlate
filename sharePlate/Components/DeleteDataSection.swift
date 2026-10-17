import SwiftUI

struct DeleteDataSection: View {
    @Environment(SupabaseAuthService.self) private var auth
    @Environment(LocalDataStore.self) private var store
    @Environment(LocationManager.self) private var location
    @State private var showConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Your data").font(AppFont.title3)
            Text("SharePlate creates an anonymous account for your listings and reservations. You can delete it and its data here.")
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.mutedText)
            Button { showConfirmation = true } label: {
                Label("Delete my data", systemImage: "trash")
            }
            .buttonStyle(SecondaryButtonStyle(tint: Theme.Palette.urgentRed))
            .disabled(isDeleting)
        }
        .foregroundStyle(Theme.Palette.primaryText)
        .confirmationDialog("Delete your account and data?", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Delete my data", role: .destructive) { Task { await deleteData() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your anonymous account, listings, uploaded photos, reservations, messages, and other account data. Your listings will disappear and your reservations will be released. This cannot be undone.")
        }
        .alert("Couldn't delete data", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func deleteData() async {
        isDeleting = true
        defer { isDeleting = false }
        do { try await auth.deleteData(store: store, location: location) }
        catch let error as AccountDeletionError { errorMessage = error.localizedDescription }
        catch { errorMessage = AccountDeletionError.unfinished.localizedDescription }
    }
}
