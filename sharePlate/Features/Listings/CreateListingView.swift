//
//  CreateListingView.swift
//  sharePlate
//
//  Frictionless, mostly tap-based posting flow designed to take under 30s.
//

import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

struct CreateListingView: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    /// When set, this post is surplus food from a claimed pantry rather than
    /// an individual donor — tags the listing and pre-fills its location.
    var pantryResource: FoodResource? = nil

    @State private var category: FoodCategory?
    @State private var otherCategoryLabel = ""
    @State private var packageCount: Int = 2
    @State private var maxPerBooking: Int = 1
    @State private var handoffMode: DonorHandoffMode = .pickup
    @State private var deadlinePreset: DeadlinePreset = .oneHour
    @State private var pickupNotes = ""
    @State private var pickupAddress = ""
    @State private var dropOffRadius: DropOffRadius = .threeMiles
    @State private var dropOffAreaLabel = "Near you"
    @State private var handoffSpot: HandoffSpot?
    @State private var readyBy: ReservationTimeslot = .in30Minutes

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoPreview: UIImage?
    @State private var photoData: Data?
    @State private var isLoadingPhoto = false
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var canSubmit: Bool {
        guard photoData != nil else { return false }
        guard category != nil else { return false }
        guard handoffSpot != nil else { return false }
        if category == .other && otherCategoryLabel.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        if handoffMode == .dropOff {
            return true
        }
        return !pickupAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let pantryResource {
                        pantryBanner(pantryResource)
                    }
                    photoStep
                    categoryStep
                    packageCountStep
                    if packageCount > 1 {
                        maxPerBookingStep
                    }
                    deadlineStep
                    handoffModeStep
                    if handoffMode == .dropOff {
                        dropOffRadiusStep
                    } else {
                        pickupAddressStep
                    }
                    if handoffMode == .dropOff {
                        dropOffDetailsStep
                    } else {
                        pickupInstructionsStep
                    }
                }
                .padding(Theme.Spacing.lg)
                .padding(.bottom, 90)
            }
            .screenBackground()
            .navigationTitle("Share Food")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { postBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                photoLoadTask?.cancel()
                if newItems.count > 1 {
                    selectedPhotoItems = Array(newItems.prefix(1))
                    return
                }
                photoLoadTask = Task { await loadPhoto(from: newItems.first) }
            }
            .onDisappear {
                photoLoadTask?.cancel()
            }
            .onChange(of: handoffMode) { _, mode in
                if mode == .dropOff {
                    Task { await refreshDropOffAreaLabel() }
                }
            }
            .onChange(of: packageCount) { _, count in
                maxPerBooking = min(maxPerBooking, max(1, count))
            }
            .task {
                if let pantryResource, pickupAddress.isEmpty {
                    pickupAddress = pantryResource.address
                }
                if handoffMode == .dropOff {
                    await refreshDropOffAreaLabel()
                }
            }
            .alert("Couldn’t post food", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Steps

    private func pantryBanner(_ resource: FoodResource) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(Theme.Palette.primaryGreen)
            Text("Posting surplus food as \(resource.name)")
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.primaryText)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.primaryGreen.opacity(0.1))
        .boxBorder(Theme.Palette.primaryGreen.opacity(0.3))
    }

    private var photoStep: some View {
        PhotosPicker(
            selection: $selectedPhotoItems,
            maxSelectionCount: 1,
            matching: .images,
            preferredItemEncoding: .compatible,
            photoLibrary: .shared()
        ) {
            Group {
                if isLoadingPhoto {
                    VStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Text("Processing photo…")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(Theme.Palette.cardBackground)
                    .boxBorder()
                } else if let photoPreview {
                    Image(uiImage: photoPreview)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            Label("Change photo", systemImage: "photo")
                                .font(AppFont.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
                                .padding(Theme.Spacing.sm)
                        }
                        .boxBorder()
                } else {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "camera.fill")
                        Text("Add one photo (required)")
                            .font(AppFont.headline)
                    }
                    .foregroundStyle(Theme.Palette.accentOrange)
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .background(Theme.Palette.accentOrange.opacity(0.12))
                    .boxBorder()
                }
            }
        }
        .disabled(isLoadingPhoto || isSaving)
    }

    private var categoryStep: some View {
        stepContainer(number: 1, title: "What kind of food?") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(FoodCategory.allCases) { option in
                        ChoiceTile(
                            title: option.displayName,
                            symbol: option.symbol,
                            isSelected: category == option
                        ) {
                            category = option
                            if option != .other {
                                otherCategoryLabel = ""
                            }
                        }
                    }
                }

                if category == .other {
                    TextField("Describe the food (e.g. baby formula, pet food)", text: $otherCategoryLabel)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .padding(12)
                        .background(Theme.Palette.cardBackground)
                        .boxBorder()
                }
            }
        }
    }

    private var packageCountStep: some View {
        stepContainer(number: 2, title: "How many packages?") {
            PackageCountPicker(
                selection: $packageCount,
                range: 1...8,
                label: "packages"
            )
        }
    }

    private var maxPerBookingStep: some View {
        stepContainer(number: 3, title: "Max per booking") {
            MaxPerBookingPicker(selection: $maxPerBooking, totalPackages: packageCount)
        }
    }

    private var deadlineStep: some View {
        stepContainer(
            number: packageCount > 1 ? 4 : 3,
            title: handoffMode == .dropOff ? "Deliver before" : "Pick up before"
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(DeadlinePreset.allCases) { preset in
                        SegmentButton(title: preset.displayName, isSelected: deadlinePreset == preset) {
                            deadlinePreset = preset
                        }
                    }
                }
                Text(handoffMode == .dropOff
                     ? "You must deliver by \(deadlinePreset.date().formatted(date: .abbreviated, time: .shortened))"
                     : "Expires \(deadlinePreset.date().formatted(date: .abbreviated, time: .shortened))")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }

    private var handoffModeStep: some View {
        stepContainer(number: packageCount > 1 ? 5 : 4, title: "Pickup or drop off?") {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(DonorHandoffMode.allCases) { mode in
                    SegmentButton(title: mode.displayName, isSelected: handoffMode == mode) {
                        handoffMode = mode
                    }
                }
            }
        }
    }

    private var dropOffRadiusStep: some View {
        stepContainer(number: packageCount > 1 ? 6 : 5, title: "How far will you travel?") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(DropOffRadius.allCases) { radius in
                        SegmentButton(title: radius.displayName, isSelected: dropOffRadius == radius) {
                            dropOffRadius = radius
                        }
                    }
                }

                Text("Your listing shows near \(dropOffAreaLabel). Reservers must be within this radius and share their address.")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }

    private var dropOffDetailsStep: some View {
        stepContainer(number: packageCount > 1 ? 7 : 6, title: "How will you drop off?") {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Drop-off method")
                        .font(AppFont.subheadlineMedium)
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(HandoffSpot.allCases) { spot in
                            let selected = handoffSpot == spot
                            Button {
                                handoffSpot = spot
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: spot.symbol)
                                    Text(spot.displayName(isDropOff: true))
                                        .font(AppFont.footnote)
                                }
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(selected ? Theme.Palette.primaryGreen.opacity(0.12) : Theme.Palette.cardBackground)
                                .foregroundStyle(selected ? Theme.Palette.primaryGreen : Theme.Palette.primaryText)
                                .boxBorder(selected ? Theme.Palette.primaryGreen : Theme.Palette.hairline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Ready to leave by")
                        .font(AppFont.subheadlineMedium)
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(ReservationTimeslot.allCases) { slot in
                            SegmentButton(title: slot.displayName, isSelected: readyBy == slot) {
                                readyBy = slot
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Drop-off note (optional)")
                        .font(AppFont.subheadlineMedium)
                    TextField("e.g. text when you're 1 min away", text: $pickupNotes, axis: .vertical)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(2...3)
                        .padding(12)
                        .background(Theme.Palette.cardBackground)
                        .boxBorder()
                }
            }
        }
    }

    private var pickupAddressStep: some View {
        stepContainer(number: packageCount > 1 ? 6 : 5, title: "Pickup address") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                TextField("1234 W Main St, Chicago, IL 60607", text: $pickupAddress, axis: .vertical)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(2...3)
                    .padding(12)
                    .background(Theme.Palette.cardBackground)
                    .boxBorder()

                Button {
                    useCurrentLocation()
                } label: {
                    Label("Use my current location", systemImage: "location.fill")
                        .font(AppFont.subheadlineMedium)
                        .foregroundStyle(Theme.Palette.primaryGreen)
                }

                Text("The exact address stays private until someone reserves.")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }

    private var pickupInstructionsStep: some View {
        stepContainer(number: packageCount > 1 ? 7 : 6, title: "How should they pick up?") {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Handoff type")
                        .font(AppFont.subheadlineMedium)
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(HandoffSpot.allCases) { spot in
                            let selected = handoffSpot == spot
                            Button {
                                handoffSpot = spot
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: spot.symbol)
                                    Text(spot.displayName(isDropOff: false))
                                        .font(AppFont.footnote)
                                }
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(selected ? Theme.Palette.primaryGreen.opacity(0.12) : Theme.Palette.cardBackground)
                                .foregroundStyle(selected ? Theme.Palette.primaryGreen : Theme.Palette.primaryText)
                                .boxBorder(selected ? Theme.Palette.primaryGreen : Theme.Palette.hairline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Food ready by")
                        .font(AppFont.subheadlineMedium)
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(ReservationTimeslot.allCases) { slot in
                            SegmentButton(title: slot.displayName, isSelected: readyBy == slot) {
                                readyBy = slot
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Pickup note (optional)")
                        .font(AppFont.subheadlineMedium)
                    TextField("e.g. ring doorbell, blue cooler by gate", text: $pickupNotes, axis: .vertical)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(2...3)
                        .padding(12)
                        .background(Theme.Palette.cardBackground)
                        .boxBorder()
                }
            }
        }
    }

    private var postBar: some View {
        Button {
            submit()
        } label: {
            Label(isSaving ? "Posting…" : "Post Food", systemImage: "paperplane.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canSubmit || isSaving || isLoadingPhoto)
        .opacity(canSubmit && !isSaving && !isLoadingPhoto ? 1 : 0.5)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Palette.backgroundCream)
    }

    // MARK: - Building blocks

    private func stepContainer<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(number)")
                    .font(AppFont.captionBold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.Palette.primaryGreen)
                    .boxBorder(Theme.Palette.primaryGreen.opacity(0.5))
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(Theme.Palette.primaryText)
            }
            content()
        }
    }

    // MARK: - Actions

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else {
            photoPreview = nil
            photoData = nil
            return
        }

        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        let rawData = await Task.detached(priority: .userInitiated) {
            try? await item.loadTransferable(type: Data.self)
        }.value

        guard !Task.isCancelled else { return }
        guard let rawData else { return }

        let processed = await Task.detached(priority: .userInitiated) {
            Self.downscaledPhotoData(rawData)
        }.value
        guard !Task.isCancelled else { return }

        photoData = processed
        photoPreview = UIImage(data: processed)
    }

    /// Downscale large photos so they store efficiently in SwiftData.
    private static func downscaledPhotoData(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxDimension: CGFloat = 1200
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        if scale >= 1 {
            return image.jpegData(compressionQuality: 0.7) ?? data
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7) ?? data
    }

    private func useCurrentLocation() {
        let coordinate = location.mapCenter
        Task {
            let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let request = MKReverseGeocodingRequest(location: loc),
                  let item = try? await request.mapItems.first,
                  let fullAddress = item.address?.fullAddress else { return }
            pickupAddress = fullAddress
        }
    }

    /// Derives a coarse public area label (typically the city) from the address.
    private func areaLabel(from address: String) -> String {
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 { return parts[parts.count - 2] }
        return parts.first ?? "Nearby"
    }

    private func areaFromCoordinate(_ coordinate: CLLocationCoordinate2D) async -> String {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: loc),
              let item = try? await request.mapItems.first,
              let fullAddress = item.address?.fullAddress else {
            return "Near you"
        }
        return areaLabel(from: fullAddress)
    }

    private func refreshDropOffAreaLabel() async {
        dropOffAreaLabel = await areaFromCoordinate(location.mapCenter)
    }

    private func submit() {
        guard let category, let photoData, let handoffSpot else { return }
        errorMessage = nil
        isSaving = true
        let fallback = location.mapCenter
        let deadline = deadlinePreset.date()
        let note = pickupNotes.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                if handoffMode == .dropOff {
                    let area: String
                    if let pantryResource {
                        area = pantryResource.name
                    } else {
                        area = await areaFromCoordinate(fallback)
                    }
                    let instructions = ReservationCoordination.publishedAtPost(
                        meetupAddress: "Near \(area)",
                        handoffSpot: handoffSpot,
                        readyBy: readyBy,
                        providerNote: note,
                        latitude: fallback.latitude,
                        longitude: fallback.longitude
                    )
                    try await store.createListing(
                        category: category,
                        customTitle: category == .other ? otherCategoryLabel.trimmingCharacters(in: .whitespaces) : nil,
                        packageCount: packageCount,
                        maxPackagesPerBooking: maxPerBooking,
                        pickupType: handoffMode.pickupType,
                        photo: photoData,
                        pickupAddress: "Within \(dropOffRadius.displayName)",
                        area: area,
                        latitude: fallback.latitude,
                        longitude: fallback.longitude,
                        pickupDeadline: deadline,
                        pickupNotes: note.isEmpty ? nil : note,
                        pickupInstructions: instructions,
                        dropOffRadiusMeters: dropOffRadius.meters,
                        pantryGCFDLocationID: pantryResource?.gcfdLocationID
                    )
                } else {
                    let address = pickupAddress.trimmingCharacters(in: .whitespaces)
                    var resolved = pantryResource?.coordinate ?? fallback
                    if let request = MKGeocodingRequest(addressString: address),
                       let item = try? await request.mapItems.first {
                        resolved = item.location.coordinate
                    }
                    let instructions = ReservationCoordination.publishedAtPost(
                        meetupAddress: address,
                        handoffSpot: handoffSpot,
                        readyBy: readyBy,
                        providerNote: note,
                        latitude: resolved.latitude,
                        longitude: resolved.longitude
                    )
                    try await store.createListing(
                        category: category,
                        customTitle: category == .other ? otherCategoryLabel.trimmingCharacters(in: .whitespaces) : nil,
                        packageCount: packageCount,
                        maxPackagesPerBooking: maxPerBooking,
                        pickupType: handoffMode.pickupType,
                        photo: photoData,
                        pickupAddress: address,
                        area: pantryResource?.name ?? areaLabel(from: address),
                        latitude: resolved.latitude,
                        longitude: resolved.longitude,
                        pickupDeadline: deadline,
                        pickupNotes: note.isEmpty ? nil : note,
                        pickupInstructions: instructions,
                        pantryGCFDLocationID: pantryResource?.gcfdLocationID
                    )
                }
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}

// MARK: - Selectable controls

private struct ChoiceTile: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(AppFont.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(8)
            .background(isSelected ? Theme.Palette.primaryGreen.opacity(0.12) : Theme.Palette.cardBackground)
            .foregroundStyle(isSelected ? Theme.Palette.primaryGreen : Theme.Palette.primaryText)
            .boxBorder(isSelected ? Theme.Palette.primaryGreen : Theme.Palette.hairline)
        }
        .buttonStyle(.plain)
    }
}

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.footnote)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 4)
                .background(isSelected ? Theme.Palette.primaryGreen : Theme.Palette.cardBackground)
                .foregroundStyle(isSelected ? Color.white : Theme.Palette.primaryText)
                .boxBorder(isSelected ? Theme.Palette.primaryGreen.opacity(0.5) : Theme.Palette.hairline)
        }
        .buttonStyle(.plain)
    }
}
