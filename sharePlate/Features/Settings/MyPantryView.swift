//
//  MyPantryView.swift
//  sharePlate
//
//  Dashboard for a claimed pantry: toggle temporarily-closed, post surplus
//  food under the pantry's name, see what's currently posted, or release
//  the claim back to the read-only directory.
//

import SwiftUI
import SwiftData

struct MyPantryView: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Query private var resources: [FoodResource]
    @Query(sort: \FoodListing.createdAt, order: .reverse) private var allListings: [FoodListing]

    let claim: PantryClaim

    @State private var closedNote: String
    @State private var isUpdatingClosed = false
    @State private var showCreate = false
    @State private var showReleaseConfirm = false
    @State private var isReleasing = false
    @State private var errorMessage: String?

    init(claim: PantryClaim) {
        self.claim = claim
        _closedNote = State(initialValue: claim.closedNote ?? "")
    }

    private var resource: FoodResource? {
        resources.first { $0.gcfdLocationID == claim.gcfdLocationID }
    }

    private var myListings: [FoodListing] {
        allListings.filter { $0.pantryGCFDLocationID == claim.gcfdLocationID && $0.effectiveStatus != .pickedUp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    closedToggleCard
                    postButton
                    listingsSection
                    releaseButton
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("My Pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateListingView(pantryResource: resource)
            }
            .confirmationDialog(
                "Release this pantry?",
                isPresented: $showReleaseConfirm,
                titleVisibility: .visible
            ) {
                Button("Release", role: .destructive) { release() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It returns to the read-only directory. Anyone can claim it afterward.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(claim.pantryName)
                .font(AppFont.title2)
                .foregroundStyle(Theme.Palette.primaryText)
            if let resource {
                Text(resource.address)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closedToggleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Toggle(isOn: Binding(
                get: { claim.isTemporarilyClosed },
                set: { setClosed($0) }
            )) {
                Text("Temporarily closed")
                    .font(AppFont.headline)
            }
            .disabled(isUpdatingClosed)
            .tint(Theme.Palette.urgentRed)

            if claim.isTemporarilyClosed {
                TextField("Note for neighbors (e.g. \"Out of food until Thursday\")", text: $closedNote, axis: .vertical)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(2...3)
                    .padding(12)
                    .background(Theme.Palette.backgroundCream)
                    .boxBorder()
                    .onSubmit { setClosed(true) }
            }
        }
        .cardStyle()
    }

    private var postButton: some View {
        Button {
            showCreate = true
        } label: {
            Label("Post Surplus Food", systemImage: "plus")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private var listingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Active listings")
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            if myListings.isEmpty {
                Text("Surplus food you post shows here.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.lg)
                    .cardStyle(padding: 0)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(myListings) { listing in
                        ListingCard(
                            listing: listing,
                            distanceText: location.distanceText(to: listing.coordinate)
                        )
                    }
                }
            }
        }
    }

    private var releaseButton: some View {
        Button(role: .destructive) {
            showReleaseConfirm = true
        } label: {
            Text(isReleasing ? "Releasing…" : "Release This Pantry")
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.urgentRed)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isReleasing)
    }

    private func setClosed(_ isClosed: Bool) {
        isUpdatingClosed = true
        Task {
            do {
                try await store.setPantryClosed(claim, isClosed: isClosed, note: closedNote)
                isUpdatingClosed = false
            } catch {
                isUpdatingClosed = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func release() {
        isReleasing = true
        Task {
            do {
                try await store.releasePantryClaim(claim)
                isReleasing = false
                dismiss()
            } catch {
                isReleasing = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
