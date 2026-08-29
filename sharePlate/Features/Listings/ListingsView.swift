//
//  ListingsView.swift
//  sharePlate
//

import SwiftUI
import SwiftData

struct ListingsView: View {
    @Environment(LocationManager.self) private var location
    @Query(sort: \FoodListing.createdAt, order: .reverse) private var listings: [FoodListing]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var displayed: [FoodListing] = []
    @State private var showCreate = false
    @State private var navigationPath = NavigationPath()

    private var listingsToken: Int {
        var hasher = Hasher()
        for listing in listings {
            hasher.combine(listing.remoteID)
            hasher.combine(listing.statusRaw)
        }
        return hasher.finalize()
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                SearchBox(text: $searchText, prompt: "Search food listings")
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.backgroundCream)

                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)

                Group {
                    if displayed.isEmpty {
                        ContentUnavailableView {
                            Label("No free food right now", systemImage: "takeoutbag.and.cup.and.straw")
                        } description: {
                            Text(searchText.isEmpty
                                 ? "Be the first to share extra food with your neighbors."
                                 : "No listings match your search.")
                        } actions: {
                            if searchText.isEmpty {
                                Button {
                                    showCreate = true
                                } label: {
                                    Label("Post Food", systemImage: "plus")
                                }
                                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                            }
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: Theme.Spacing.md) {
                                ForEach(displayed) { listing in
                                    Button {
                                        navigationPath.append(LocationDetail.listing(listing.persistentModelID))
                                    } label: {
                                        ListingCard(listing: listing, distanceText: location.distanceText(to: listing.coordinate))
                                    }
                                    .buttonStyle(PlainRowButtonStyle())
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .screenBackground()
            .navigationTitle("Food")
            .navigationDestination(for: LocationDetail.self) { detail in
                LocationDetailScreen(detail: detail)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.Palette.primaryGreen)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateListingView()
            }
            .onAppear {
                debouncedSearchText = searchText
                rebuildDisplayed()
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
            .onChange(of: debouncedSearchText) { _, _ in rebuildDisplayed() }
            .onChange(of: listingsToken) { _, _ in rebuildDisplayed() }
        }
    }

    private func rebuildDisplayed() {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        displayed = listings.filter { listing in
            guard listing.effectiveStatus == .available else { return false }
            if query.isEmpty { return true }
            return listing.title.lowercased().contains(query)
                || listing.category.displayName.lowercased().contains(query)
                || listing.areaLabel.lowercased().contains(query)
        }
    }
}
