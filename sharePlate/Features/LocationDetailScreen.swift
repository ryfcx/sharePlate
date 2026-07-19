//
//  LocationDetailScreen.swift
//  sharePlate
//

import SwiftUI
import SwiftData

struct LocationDetailScreen: View {
    let detail: LocationDetail

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodListing.createdAt, order: .reverse) private var listings: [FoodListing]
    @Query(sort: \FoodResource.name) private var resources: [FoodResource]

    var body: some View {
        Group {
            switch detail {
            case .listing(let id):
                listingContent(for: id)
            case .resource(let id):
                if let resource = resources.first(where: { $0.persistentModelID == id }) {
                    ResourceDetailView(resource: resource)
                } else {
                    unavailable("This resource is no longer available.")
                }
            }
        }
    }

    @ViewBuilder
    private func listingContent(for id: PersistentIdentifier) -> some View {
        if let listing = listings.first(where: { $0.persistentModelID == id }) {
            if listing.effectiveStatus == .pickedUp || listing.effectiveStatus == .expired {
                unavailable("This listing is no longer available.")
                    .onAppear { dismissSoon() }
            } else {
                ListingHandoffGate(listing: listing)
            }
        } else {
            unavailable("This listing is no longer available.")
                .onAppear { dismissSoon() }
        }
    }

    private func dismissSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "takeoutbag.and.cup.and.straw")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Palette.mutedText)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}
