import SwiftUI

struct BlockedUsersView: View {
    @Environment(LocalDataStore.self) private var store
    @State private var selectedUser: BlockedUser?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.blockedUsers.isEmpty {
                Text("No blocked users")
                    .foregroundStyle(Theme.Palette.mutedText)
            }
            ForEach(store.blockedUsers) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(AppFont.body)
                        Text("Blocked on \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(AppFont.caption)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    Spacer()
                    Button { selectedUser = user } label: {
                        Text("Unblock")
                            .font(AppFont.button)
                            .foregroundStyle(Theme.Palette.primaryGreen)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .boxBorder()
                    }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                }
                .listRowBackground(Theme.Palette.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Blocked users")
        .task { await store.syncBlockedUsers() }
        .confirmationDialog("Unblock this user?", isPresented: Binding(
            get: { selectedUser != nil },
            set: { if !$0 { selectedUser = nil } }
        ), titleVisibility: .visible) {
            if let user = selectedUser {
                Button("Unblock") { Task { await unblock(user) } }
            }
            Button("Cancel", role: .cancel) { selectedUser = nil }
        } message: {
            Text("Their available listings will appear again. They can reserve your food again unless they have also blocked you.")
        }
        .alert("Couldn't unblock user", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func unblock(_ user: BlockedUser) async {
        isSaving = true
        defer { isSaving = false; selectedUser = nil }
        do {
            try await store.unblockUser(user.id)
        } catch {
            errorMessage = String(localized: "Check your connection and try again.")
        }
    }
}
