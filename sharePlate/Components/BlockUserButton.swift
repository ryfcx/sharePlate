import SwiftUI

struct BlockUserButton: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session
    @Environment(\.dismiss) private var dismiss
    let listing: FoodListing
    @State private var showConfirmation = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var target: String? {
        session.matches(listing.postedByDeviceID) ? listing.claimedByDeviceID : listing.postedByDeviceID
    }

    var body: some View {
        if let target, UUID(uuidString: target) != nil, !session.matches(target), !store.isUserBlocked(target) {
            Button {
                showConfirmation = true
            } label: {
                Label("Block user", systemImage: "person.crop.circle.badge.xmark")
            }
            .disabled(isSaving)
            .confirmationDialog("Block this user?", isPresented: $showConfirmation, titleVisibility: .visible) {
                Button("Block user", role: .destructive) {
                    Task { await block(target) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their listings will be hidden and new reservations and messages between you will be blocked. Existing reservations stay in Activity so they can be completed. You can unblock them in Settings.")
            }
            .alert("Couldn't block user", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func block(_ target: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.blockUser(target, name: String(localized: "User from \(listing.title)"))
            if !ActiveReservationView.isActiveParticipant(listing, session: session) {
                dismiss()
            }
        } catch {
            errorMessage = String(localized: "Check your connection and try again.")
        }
    }
}
