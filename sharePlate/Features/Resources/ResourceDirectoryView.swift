//
// resourcedirectoryview.swift
// shareplate
//

import SwiftUI
import SwiftData
import CoreLocation

struct ResourceDirectoryView: View {
    @Environment(LocationManager.self) private var location
    @Query(sort: \FoodResource.name) private var resources: [FoodResource]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedTypes: Set<ResourceType> = []
    @State private var openNowOnly = false
    @State private var sortByDistance = false
    @State private var displayed: [FoodResource] = []
    @State private var navigationPath = NavigationPath()

    private var filterToken: String {
        "\(debouncedSearchText)|\(openNowOnly)|\(sortByDistance)|\(selectedTypes.map(\.rawValue).sorted().joined())|\(resources.count)"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                SearchBox(text: $searchText, prompt: "Search ZIP, city, or name")
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.xs)
                    .background(Theme.Palette.backgroundCream)

                filterBar

                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        if displayed.isEmpty {
                            ContentUnavailableView(
                                "No resources found",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different search or clear your filters.")
                            )
                            .padding(.top, 60)
                        }
                        ForEach(displayed) { resource in
                            Button {
                                navigationPath.append(LocationDetail.resource(resource.persistentModelID))
                            } label: {
                                ResourceRow(resource: resource, distanceText: location.distanceText(to: resource.coordinate))
                            }
                            .buttonStyle(PlainRowButtonStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                }
            }
            .screenBackground()
            .navigationTitle("Resources")
            .navigationDestination(for: LocationDetail.self) { detail in
                LocationDetailScreen(detail: detail)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.Spacing.md) {
                        Menu {
                            Toggle("Sort by distance", isOn: $sortByDistance)
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        SharePlateLogoView()
                    }
                }
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
            .onChange(of: filterToken) { _, _ in rebuildDisplayed() }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                FilterChip(title: "Open now", systemImage: "clock", isSelected: openNowOnly) {
                    withoutAnimation { openNowOnly.toggle() }
                }
                ForEach(ResourceType.allCases) { type in
                    FilterChip(title: type.shortName, systemImage: type.symbol, isSelected: selectedTypes.contains(type), tint: type.tint) {
                        withoutAnimation {
                            if selectedTypes.contains(type) { selectedTypes.remove(type) }
                            else { selectedTypes.insert(type) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Palette.backgroundCream)
    }

    private func rebuildDisplayed() {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        var result = resources.filter { resource in
            if !selectedTypes.isEmpty && !selectedTypes.contains(resource.type) { return false }
            if openNowOnly && resource.isOpenNow != true { return false }
            if !query.isEmpty {
                return resource.name.lowercased().contains(query)
                    || resource.address.lowercased().contains(query)
            }
            return true
        }
        if sortByDistance {
            let center = location.mapCenter
            let from = CLLocation(latitude: center.latitude, longitude: center.longitude)
            result.sort { a, b in
                let da = from.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
                let db = from.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                return da < db
            }
        }
        displayed = result
    }
}
