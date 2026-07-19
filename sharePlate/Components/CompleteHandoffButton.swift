//
//  CompleteHandoffButton.swift
//  sharePlate
//

import SwiftUI

extension FoodListing {
    func canMarkPickedUp(for session: SessionContext) -> Bool {
        guard status != .pickedUp else { return false }

        let isOwner = session.matches(postedByDeviceID)
        let isClaimer = session.matches(claimedByDeviceID)
        guard isOwner || isClaimer else { return false }

        if hasActiveHandoff {
            return true
        }

        if isOwner && status == .available && !isExpired {
            return true
        }

        return false
    }

    var completeHandoffTitle: String {
        isDropOff ? "Mark as dropped off" : "Mark as picked up"
    }

    var completeHandoffSwipeTitle: String {
        isDropOff ? "Dropped off" : "Picked up"
    }

    var completeHandoffConfirmationMessage: String {
        if shouldReopenAfterHandoffCompletion {
            let remaining = packagesRemaining
            let unit = remaining == 1 ? "package" : "packages"
            return "Confirm this handoff is complete? \(remaining) \(unit) will stay listed for others."
        }
        if isDropOff {
            return "Confirm the food was dropped off? This listing will be removed for everyone."
        }
        return "Confirm the food was picked up? This listing will be removed for everyone."
    }
}

struct CompleteHandoffButton: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session

    let listing: FoodListing

    @State private var showConfirm = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        if listing.canMarkPickedUp(for: session) {
            Button {
                showConfirm = true
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Label(listing.completeHandoffTitle, systemImage: "checkmark.circle.fill")
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isWorking)
            .confirmationDialog(
                listing.completeHandoffTitle,
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button(listing.completeHandoffTitle, role: .destructive) {
                    Task { await completeHandoff() }
                }
                .disabled(isWorking)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(listing.completeHandoffConfirmationMessage)
            }
            .alert("Couldn't complete handoff", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func completeHandoff() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await store.markPickedUp(listing)
        } catch {
            errorMessage = handoffErrorMessage(for: error)
        }
    }

    private func handoffErrorMessage(for error: Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lower = detail.lowercased()
        if lower.contains("row-level security") || lower.contains("complete_listing_handoff") {
            return "Server permissions blocked this update. In Supabase → SQL Editor, run the full supabase/listings_rls.sql file, then try again."
        }
        if let sync = error as? SyncError, case .remoteUpdateFailed(let message) = sync {
            return message
        }
        return detail
    }
}
