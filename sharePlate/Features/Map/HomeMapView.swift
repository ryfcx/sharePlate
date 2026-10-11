//
// homemapview.swift
// shareplate
//
// compact header map and nearby panel
//

import SwiftUI
import SwiftData
import MapKit

struct HomeMapView: View {
    @Environment(LocationManager.self) private var location
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session
    @Query private var resources: [FoodResource]
    @Query(sort: \FoodListing.createdAt, order: .reverse) private var listings: [FoodListing]

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationManager.chicago,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )
    @State private var mapHasValidSize = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedFilters: Set<MapFilterOption> = Set(MapFilterOption.allCases)
    @State private var timeWindow: MapTimeWindow = .near
    @State private var showOpenOnly = true
    @State private var showAllLocations = false
    @State private var showCreate = false
    @State private var nearbyExpanded = false
    @State private var navigationPath = NavigationPath()
    @State private var notice = LocalNotice.shared

    @State private var mapResources: [FoodResource] = []
    @State private var mapListings: [FoodListing] = []
    @State private var nearbyResources: [FoodResource] = []
    @State private var nearbyListings: [FoodListing] = []
    @State private var lastSortCenter: CLLocationCoordinate2D?
    @State private var nearbyPlaceCount = 0

    private let collapsedBarHeight: CGFloat = 56
    private let nearRadiusMeters: CLLocationDistance = 8046
    // cap pins and rows to keep scrolling smooth
    private let nearbyListLimit = 60
    private let mapPinLimit = 80

    @State private var lastOpenedHandoffRemoteID: String?

    // only refresh pins when browse data changes
    // skip handoff updates on reserved listings
    private var browseSettingsToken: String {
        let filters = selectedFilters.map(\.rawValue).sorted().joined(separator: ",")
        return "\(debouncedSearchText)|\(showOpenOnly)|\(showAllLocations)|\(timeWindow.rawValue)|\(filters)"
    }

    private var listingsCatalogToken: Int {
        var hasher = Hasher()
        hasher.combine(listings.count)
        for listing in listings {
            hasher.combine(listing.remoteID)
            hasher.combine(listing.statusRaw)
        }
        return hasher.finalize()
    }

    private var resourcesBrowseToken: Int {
        resources.count
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                header

                ZStack(alignment: .bottom) {
                    GeometryReader { geometry in
                        Group {
                            if geometry.size.width > 1, geometry.size.height > 1 {
                                map
                            } else {
                                Color.clear
                            }
                        }
                        .onAppear {
                            mapHasValidSize = geometry.size.width > 1 && geometry.size.height > 1
                        }
                        .onChange(of: geometry.size) { _, size in
                            mapHasValidSize = size.width > 1 && size.height > 1
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottomLeading) {
                        if mapHasValidSize {
                            mapLegendOverlay
                        }
                    }

                    nearbyOverlay
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(nil, value: nearbyExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.backgroundCream)
            .navigationBarHidden(true)
            .navigationDestination(for: LocationDetail.self) { detail in
                LocationDetailScreen(detail: detail)
            }
            .sheet(isPresented: $showCreate) {
                CreateListingView()
            }
            .onAppear {
                debouncedSearchText = searchText
                centerIfNeeded()
                refreshLocationCaches(forceResort: true)
                Task { await openPendingHandoffIfNeeded() }
                Task { await NearbyAlertService.refreshPantryOpenSchedule(resources: resources, near: location.mapCenter) }
            }
            .onChange(of: notice.pendingHandoffListingRemoteID) { _, _ in
                Task { await openPendingHandoffIfNeeded() }
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(280))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
            .onChange(of: location.userLocation?.latitude) { _, _ in
                refreshLocationCachesIfMoved()
                Task { await NearbyAlertService.refreshPantryOpenSchedule(resources: resources, near: location.mapCenter) }
            }
            .onChange(of: browseSettingsToken) { _, _ in
                refreshLocationCaches(forceResort: false, fitAllRegion: showAllLocations)
            }
            .onChange(of: listingsCatalogToken) { _, _ in
                refreshLocationCaches(forceResort: false, listingsOnly: true)
                Task { await NearbyAlertService.checkForNewNearbyListings(listings, near: location.mapCenter, excludingDeviceID: session.identity) }
            }
            .onChange(of: resourcesBrowseToken) { _, _ in
                refreshLocationCaches(forceResort: false, resourcesOnly: true)
                Task { await NearbyAlertService.refreshPantryOpenSchedule(resources: resources, near: location.mapCenter) }
            }
            .onChange(of: timeWindow) { _, window in
                if window == .tomorrow {
                    withoutAnimation { showOpenOnly = false }
                }
                refreshLocationCaches(forceResort: false)
            }
            .onChange(of: showAllLocations) { _, isOn in
                refreshLocationCaches(forceResort: true, fitAllRegion: isOn)
                if !isOn {
                    centerIfNeeded()
                }
            }
        }
    }

    private func openDetail(_ detail: LocationDetail) {
        navigationPath.append(detail)
    }

    private func openPendingHandoffIfNeeded() async {
        guard let remoteID = notice.pendingHandoffListingRemoteID else { return }
        guard remoteID != lastOpenedHandoffRemoteID else { return }
        if listings.first(where: { $0.remoteID == remoteID }) == nil {
            await store.syncListing(remoteID: remoteID)
        }
        guard let listing = listings.first(where: { $0.remoteID == remoteID }) else { return }
        notice.pendingHandoffListingRemoteID = nil
        lastOpenedHandoffRemoteID = remoteID
        navigationPath.append(LocationDetail.listing(listing.persistentModelID))
    }

    private func refreshLocationCachesIfMoved() {
        let center = location.mapCenter
        if let last = lastSortCenter {
            let from = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let to = CLLocation(latitude: center.latitude, longitude: center.longitude)
            guard from.distance(from: to) > 400 else { return }
        }
        refreshLocationCaches(forceResort: true)
    }

    private func refreshLocationCaches(
        forceResort: Bool,
        fitAllRegion: Bool = false,
        listingsOnly: Bool = false,
        resourcesOnly: Bool = false
    ) {
        if forceResort {
            lastSortCenter = location.mapCenter
        }

        let openOnly = MapFilterLogic.openNowApplies(showOpenOnly: showOpenOnly, showAllLocations: showAllLocations)
            && timeWindow != .tomorrow
        let applyNearRadius = MapBrowseLogic.appliesNearRadius(timeWindow) && !showAllLocations
        let query = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        let showResources = MapFilterLogic.includesResources(selected: selectedFilters)
        let showListings = MapFilterLogic.includesListings(selected: selectedFilters)
        let refreshResources = showResources && !listingsOnly
        let refreshListings = showListings && !resourcesOnly

        var filteredR = nearbyResources
        if refreshResources {
            filteredR = resources.filter { resource in
                if selectedFilters.isEmpty || !resource.matches(selectedFilters) { return false }
                if !MapBrowseLogic.resourceMatches(resource, window: timeWindow) { return false }
                if openOnly {
                    let status = resourceOpenStatus(resource)
                    if status == .closed { return false }
                }
                if !query.isEmpty {
                    return resource.name.lowercased().contains(query)
                        || resource.address.lowercased().contains(query)
                }
                return true
            }
        } else if !showResources {
            filteredR = []
        }

        var filteredL = nearbyListings
        if refreshListings {
            filteredL = listings.filter { listing in
                guard MapBrowseLogic.listingMatchesWindow(listing, window: timeWindow) else { return false }
                if openOnly, listing.isPermanent, permanentStoreStatus(listing) == .closed { return false }
                if selectedFilters.isEmpty || !listing.matches(selectedFilters) { return false }
                if !query.isEmpty {
                    return listing.title.lowercased().contains(query)
                        || listing.category.displayName.lowercased().contains(query)
                        || listing.areaLabel.lowercased().contains(query)
                }
                return true
            }
        } else if !showListings {
            filteredL = []
        }

        let permanentStoreIDs = Set(filteredL.filter(\.isPermanent).compactMap(\.pantryGCFDLocationID))
        if !permanentStoreIDs.isEmpty {
            filteredR.removeAll { resource in
                guard let id = resource.gcfdLocationID else { return false }
                return permanentStoreIDs.contains(id)
            }
        }

        let scopedR = applyNearRadius ? filteredR.filter { isNear($0.coordinate) } : filteredR
        let scopedL = applyNearRadius ? filteredL.filter { isNear($0.coordinate) } : filteredL
        let sortedR = sortedByDistance(scopedR) { $0.coordinate }
        let sortedL = sortedByDistance(scopedL) { $0.coordinate }

        if showAllLocations {
            mapResources = sortedR
            mapListings = sortedL
            nearbyResources = sortedR
            nearbyListings = sortedL
        } else {
            mapResources = Array(sortedR.prefix(mapPinLimit))
            mapListings = Array(sortedL.prefix(mapPinLimit))
            nearbyResources = Array(sortedR.prefix(nearbyListLimit))
            nearbyListings = Array(sortedL.prefix(nearbyListLimit))
        }
        nearbyPlaceCount = sortedR.count + sortedL.count

        if showAllLocations && fitAllRegion {
            let coords = sortedR.map(\.coordinate) + sortedL.map(\.coordinate)
            if let region = region(fitting: coords) {
                cameraPosition = .region(region)
            }
        }
    }

    private func isNear(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let center = location.mapCenter
        let latDelta = abs(coordinate.latitude - center.latitude)
        let lonDelta = abs(coordinate.longitude - center.longitude)
        if latDelta > 0.09 || lonDelta > 0.09 { return false }

        let from = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to) <= nearRadiusMeters
    }

    // header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                Text("SharePlate")
                    .font(AppFont.title2)
                    .foregroundStyle(Theme.Palette.primaryText)
                Spacer(minLength: 0)
                SharePlateLogoView()
            }

            SearchBox(text: $searchText, prompt: searchPrompt)

            MapTimeFilterBar(selection: $timeWindow)

            GroupedFilterBar(selected: $selectedFilters) {
                FilterChip(title: "Open now", systemImage: "clock", isSelected: showOpenOnly && !showAllLocations && timeWindow != .tomorrow) {
                    withoutAnimation {
                        if showAllLocations {
                            showAllLocations = false
                            showOpenOnly = true
                        } else if timeWindow == .tomorrow {
                            timeWindow = .today
                            showOpenOnly = true
                        } else {
                            showOpenOnly.toggle()
                        }
                    }
                }
                FilterChip(title: "All locations", systemImage: "globe", isSelected: showAllLocations) {
                    showAllLocations.toggle()
                    let showAll = showAllLocations
                    Task { @MainActor in
                        refreshLocationCaches(forceResort: true, fitAllRegion: showAll)
                        if !showAll {
                            centerIfNeeded()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Palette.backgroundCream)
    }

    private var searchPrompt: String {
        switch timeWindow {
        case .near: return String(localized: "Search nearby")
        case .today: return String(localized: "Search available today")
        case .tomorrow: return String(localized: "Search for tomorrow")
        }
    }

    private var mapLegendOverlay: some View {
        MapLegendView()
            .padding(.leading, Theme.Spacing.lg)
            .padding(.bottom, nearbyExpanded ? 388 : collapsedBarHeight + Theme.Spacing.sm)
    }

    private func permanentStoreStatus(_ listing: FoodListing) -> MapPlaceOpenStatus {
        guard let id = listing.pantryGCFDLocationID,
              let resource = resources.first(where: { $0.gcfdLocationID == id }) else {
            return listing.mapOpenStatus
        }
        return resourceOpenStatus(resource)
    }

    private func resourceOpenStatus(_ resource: FoodResource) -> MapPlaceOpenStatus {
        switch timeWindow {
        case .near, .today:
            return resource.openStatus()
        case .tomorrow:
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return resource.openStatusPreview(on: tomorrow)
        }
    }

    // map

    private var map: some View {
        Map(position: $cameraPosition) {
            if location.isAuthorized {
                UserAnnotation()
            }

            ForEach(mapResources) { resource in
                Annotation(resource.name, coordinate: resource.coordinate) {
                    Button {
                        openDetail(.resource(resource.persistentModelID))
                    } label: {
                        MapDot(status: resourceOpenStatus(resource))
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(mapListings) { listing in
                Annotation(
                    listing.isPermanent
                        ? listing.title
                        : (listing.isPantryListing
                            ? listing.areaLabel
                            : String(localized: "Near \(listing.areaLabel)")),
                    coordinate: (listing.isPermanent || listing.isStandingLocation) ? listing.coordinate : listing.publicCoordinate
                ) {
                    Button {
                        openDetail(.listing(listing.persistentModelID))
                    } label: {
                        MapPin(
                            symbol: listing.isPermanent ? "cart.fill" : listing.category.symbol,
                            color: listing.typePinColor
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            if location.isAuthorized {
                MapUserLocationButton()
            }
        }
    }

    // nearby panel over map

    private var nearbyOverlay: some View {
        VStack(spacing: 0) {
            nearbyHeaderBar
            if nearbyExpanded {
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)
                nearbyListContent
                    .frame(maxHeight: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.cardBackground)
        .animation(nil, value: nearbyExpanded)
    }

    private var nearbyHeaderBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    nearbyExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(nearbyPanelTitle)
                        .font(AppFont.headline)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(nearbyCountText)
                        .font(AppFont.caption)
                        .foregroundStyle(Theme.Palette.mutedText)
                    Image(systemName: nearbyExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.mutedText)
                        .contentTransition(.identity)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { showCreate = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.Palette.primaryGreen, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share extra food")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: collapsedBarHeight)
        .background(Theme.Palette.cardBackground)
    }

    private var nearbyListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if nearbyListings.isEmpty && nearbyResources.isEmpty {
                    Text(emptyResultsMessage)
                        .font(AppFont.subheadline)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                }

                if !nearbyListings.isEmpty {
                    if !nearbyResources.isEmpty {
                        sectionTitle("Free food")
                    }
                    ForEach(nearbyListings) { listing in
                        Button {
                            openDetail(.listing(listing.persistentModelID))
                        } label: {
                            ListingCard(
                                listing: listing,
                                distanceText: location.distanceText(to: listing.coordinate)
                            )
                        }
                        .buttonStyle(PlainRowButtonStyle())
                    }
                }

                if !nearbyResources.isEmpty {
                    if !nearbyListings.isEmpty {
                        sectionTitle("Resources")
                    }
                    ForEach(nearbyResources) { resource in
                        Button {
                            openDetail(.resource(resource.persistentModelID))
                        } label: {
                            ResourceRow(
                                resource: resource,
                                distanceText: location.distanceText(to: resource.coordinate)
                            )
                        }
                        .buttonStyle(PlainRowButtonStyle())
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.captionBold)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.xs)
    }

    private func sortedByDistance<T>(_ items: [T], coordinate: (T) -> CLLocationCoordinate2D) -> [T] {
        let center = location.mapCenter
        let from = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return items
            .map { item -> (T, CLLocationDistance) in
                let coord = coordinate(item)
                let to = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                return (item, from.distance(from: to))
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private var nearbyPanelTitle: String {
        switch timeWindow {
        case .near: return String(localized: "Nearby")
        case .today: return String(localized: "Today")
        case .tomorrow: return String(localized: "Tomorrow")
        }
    }

    private var nearbyCountText: String {
        nearbyPlaceCount == 1
            ? String(localized: "1 place")
            : String(localized: "\(nearbyPlaceCount) places")
    }

    private var emptyResultsMessage: String {
        if timeWindow == .tomorrow {
            return String(localized: "Nothing matches for tomorrow nearby. Try Today or Near.")
        }
        if timeWindow == .today {
            return String(localized: "Nothing available today matches your filters. Try Near or turn off Open now.")
        }
        if !MapFilterLogic.includesResources(selected: selectedFilters)
            && MapFilterLogic.includesListings(selected: selectedFilters) {
            return String(localized: "No free food listings match these filters nearby.")
        }
        if MapFilterLogic.includesResources(selected: selectedFilters)
            && !MapFilterLogic.includesListings(selected: selectedFilters) {
            return String(localized: "No pantry resources match these filters nearby.")
        }
        if showOpenOnly && !showAllLocations {
            return String(localized: "No open places match your search nearby. Try turning off Open now.")
        }
        return String(localized: "No places match your search.")
    }

    private func centerIfNeeded() {
        cameraPosition = .region(location.defaultRegion)
    }

    private func region(fitting coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.25, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.25, 0.05)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct MapDot: View {
    var status: MapPlaceOpenStatus

    var body: some View {
        Circle()
            .fill(status.pinColor)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .padding(8)
            .contentShape(Circle())
    }
}

private struct MapPin: View {
    let symbol: String
    var color: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(Rectangle().stroke(.white, lineWidth: 2))
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(6)
        .contentShape(Rectangle())
    }
}
