//
//  PantryClaimPickerView.swift
//  sharePlate
//
//  Search the GCFD directory and claim a pantry to manage. Claiming is
//  first-come-first-served, keyed by GCFD's own stable location id so it
//  survives the daily dataset resync — see PantryClaim.
//

import SwiftUI
import SwiftData

struct PantryClaimPickerView: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodResource.name) private var resources: [FoodResource]

    @State private var searchText = ""
    @State private var isClaiming = false
    @State private var errorMessage: String?
    @State private var pendingClaim: FoodResource?

    private var claimableResources: [FoodResource] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return resources.filter { resource in
            guard resource.gcfdLocationID != nil, resource.managedByUserID == nil else { return false }
            guard !query.isEmpty else { return true }
            return resource.name.lowercased().contains(query) || resource.address.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBox(text: $searchText, prompt: "Search pantries by name or address")
                    .padding(Theme.Spacing.lg)

                if claimableResources.isEmpty {
                    ContentUnavailableView {
                        Label("No pantries found", systemImage: "building.2")
                    } description: {
                        Text(searchText.isEmpty
                             ? "Every pantry in the directory is already claimed."
                             : "No unclaimed pantries match your search.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(claimableResources) { resource in
                                Button {
                                    pendingClaim = resource
                                } label: {
                                    ResourceRow(resource: resource)
                                }
                                .buttonStyle(PlainRowButtonStyle())
                                .disabled(isClaiming)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.lg)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Claim a Pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Claim \(pendingClaim?.name ?? "this pantry")?",
                isPresented: Binding(get: { pendingClaim != nil }, set: { if !$0 { pendingClaim = nil } }),
                titleVisibility: .visible
            ) {
                Button("Claim pantry") {
                    if let resource = pendingClaim {
                        claim(resource)
                    }
                }
                Button("Cancel", role: .cancel) { pendingClaim = nil }
            } message: {
                Text("You'll be able to post surplus food under this pantry's name and mark it temporarily closed. Anyone can see this pantry is managed once claimed.")
            }
            .alert("Couldn't claim pantry", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isClaiming {
                    ProgressView().padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                }
            }
        }
    }

    private func claim(_ resource: FoodResource) {
        pendingClaim = nil
        isClaiming = true
        Task {
            do {
                try await store.claimPantry(resource)
                isClaiming = false
                dismiss()
            } catch {
                isClaiming = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
