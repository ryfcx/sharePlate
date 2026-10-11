//
// listingdetailview.swift
// shareplate
//

import SwiftUI

struct ListingDetailView: View {
    @Environment(LocationManager.self) private var location
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session

    @Bindable var listing: FoodListing

    @State private var showReserveConfirm = false
    @State private var showPackageReserve = false
    @State private var showDropOffReserve = false
    @State private var reserveError: String?
    @State private var isReserving = false
    @State private var showReport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ListingPhotoView(listing: listing, height: 200)

                statusAndCountdown

                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title)
                        .font(AppFont.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(listing.postedRelativeText)
                        .font(AppFont.caption)
                        .foregroundStyle(Theme.Palette.mutedText)
                }

                if listing.revealsBookingCode {
                    BookingCodeCard(
                        code: listing.bookingCode,
                        caption: "Use this code at handoff."
                    )
                }

                detailsCard
                locationCard

                if canSeeExact, !listing.isDropOff {
                    DirectionsButton(coordinate: listing.coordinate, name: listing.title, address: listing.pickupAddress)
                }

                actionArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Food Listing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReport = true
                } label: {
                    Image(systemName: "flag")
                }
            }
        }
        .alert(listing.isDropOff ? "Reserve this drop off?" : "Reserve this pickup?", isPresented: $showReserveConfirm) {
            Button("Reserve") { reserve(packageCount: 1) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if listing.isStandingLocation {
                Text(listing.isDropOff
                     ? "This drop off stays available. Details unlock after you reserve."
                     : "This pickup stays available. The exact address unlocks after you reserve.")
            } else if listing.isDropOff {
                Text("Can you meet before \(listing.pickupDeadline.formatted(date: .omitted, time: .shortened))? Pickup details unlock after you reserve.")
            } else {
                Text("Can you arrive before \(listing.pickupDeadline.formatted(date: .omitted, time: .shortened))? The exact address unlocks after you reserve.")
            }
        }
        .alert("Couldn't reserve", isPresented: Binding(
            get: { reserveError != nil },
            set: { if !$0 { reserveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reserveError ?? "")
        }
        .sheet(isPresented: $showDropOffReserve) {
            DropOffReserveSheet(listing: listing) { packageCount, details in
                try await store.reserve(listing, packageCount: packageCount, dropOff: details)
            }
        }
        .sheet(isPresented: $showPackageReserve) {
            PackageReserveSheet(listing: listing) { packageCount in
                try await store.reserve(listing, packageCount: packageCount, dropOff: nil)
            }
        }
        .confirmationDialog("Report this listing", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.displayName, role: reason == .inappropriate ? .destructive : nil) {
                    store.report(listing, reason: reason, notes: nil)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // cards

    private var statusAndCountdown: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                StatusBadge(status: listing.effectiveStatus)
                Spacer(minLength: Theme.Spacing.sm)
                availabilityLine
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                StatusBadge(status: listing.effectiveStatus)
                availabilityLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var availabilityLine: some View {
        if listing.isPermanent || listing.isStandingLocation {
            Text("Always available")
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.primaryGreen)
        } else {
            CountdownText(deadline: listing.pickupDeadline)
                .font(AppFont.subheadlineMedium)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: Theme.Spacing.lg) {
            infoRow(icon: listing.category.symbol, title: "Food type", value: listing.category.displayName)
            divider
            infoRow(icon: "shippingbox.fill", title: "Packages", value: listing.packageSummaryLabel)
            if listing.packageCount > 0, listing.effectiveStatus == .available, listing.effectivePackagesRemaining < listing.packageCount {
                divider
                infoRow(
                    icon: "cube.box",
                    title: "Available now",
                    value: String(localized: "\(listing.effectivePackagesRemaining) of \(listing.packageCount) packages")
                )
            }
            divider
            infoRow(icon: listing.pickupType.symbol, title: listing.isDropOff ? "Handoff" : "Pickup method", value: handoffMethodText)
            divider
            infoRow(
                icon: "clock",
                title: listing.isPermanent ? "Hours" : (listing.isStandingLocation ? "Availability" : "Pickup deadline"),
                value: listing.isPermanent ? "Open 24 Hours" : (listing.isStandingLocation ? "Always available" : listing.pickupDeadline.formatted(date: .abbreviated, time: .shortened))
            )
        }
        .cardStyle()
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if listing.isDropOff {
                dropOffLocationContent
            } else if canSeeExact {
                infoRow(icon: "mappin.and.ellipse", title: "Pickup address", value: pickupLine)
                if let notes = listing.pickupNotes, !notes.isEmpty {
                    divider
                    translatableInfoRow(icon: "note.text", title: "Pickup note", value: notes)
                }
            } else {
                infoRow(
                    icon: "mappin.circle",
                    title: "Approximate area",
                    value: String(localized: "Near \(listing.areaLabel)")
                )
                divider
                Label("Reserve the pickup to unlock the exact address.", systemImage: "lock.fill")
                    .font(AppFont.subheadlineMedium)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if listing.hasPublishedPickupInstructions {
                    divider
                    publicPickupSummary
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var dropOffLocationContent: some View {
        let radius = listing.dropOffRadiusLabel ?? String(localized: "nearby")
        infoRow(
            icon: "location.circle",
            title: "Drop-off radius",
            value: String(localized: "Donor will travel up to \(radius) from near \(listing.areaLabel)")
        )
        if canSeeExact {
            divider
            Label("Coordinate the exact meetup spot using messages below.", systemImage: "bubble.left.and.bubble.right")
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
        } else {
            divider
            Label("Reserve to coordinate where to meet within the donor's travel radius.", systemImage: "lock.fill")
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            if listing.hasPublishedPickupInstructions {
                divider
                publicPickupSummary
            }
        }
        if let notes = listing.pickupNotes, !notes.isEmpty {
            divider
            translatableInfoRow(icon: "note.text", title: "Note", value: notes)
        }
    }

    // action area

    @ViewBuilder
    private var actionArea: some View {
        let status = listing.effectiveStatus

        if listing.isPermanent {
            EmptyView()
        } else if isMine {
            ownerControls(status: status)
        } else {
            switch status {
            case .available:
                Button {
                    if listing.isDropOff {
                        showDropOffReserve = true
                    } else if listing.needsPackageSelectionOnReserve {
                        showPackageReserve = true
                    } else {
                        showReserveConfirm = true
                    }
                } label: {
                    Group {
                        if isReserving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label(listing.isDropOff ? "Reserve Drop Off" : "Reserve Pickup", systemImage: "hand.raised.fill")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 20)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isReserving)
            case .reserved, .readyForPickup:
                if claimedByMe {
                    Label("Handoff in progress", systemImage: "arrow.triangle.2.circlepath")
                        .font(AppFont.subheadlineMedium)
                        .foregroundStyle(Theme.Palette.primaryGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    reservedByOtherControls
                }
            case .pickedUp:
                statusNote("This food has already been picked up.")
            case .expired:
                statusNote("This listing has expired.")
            }
        }
    }

    @ViewBuilder
    private func ownerControls(status: ListingStatus) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Label("This is your listing.", systemImage: "person.crop.circle.fill")
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.primaryGreen)
                .frame(maxWidth: .infinity, alignment: .leading)

            if listing.claimedByDeviceID != nil {
                Label("Handoff in progress", systemImage: "list.bullet.clipboard.fill")
                    .font(AppFont.subheadlineMedium)
                    .foregroundStyle(Theme.Palette.primaryGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if status == .reserved {
                statusNote("Someone reserved this. Hold it until they arrive.")
            }

            if !listing.waitlistDeviceIDs.isEmpty {
                Label("\(listing.waitlistDeviceIDs.count) waiting if it reopens", systemImage: "bell.badge")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if status == .reserved || status == .readyForPickup {
                CompleteHandoffButton(listing: listing)
            }
        }
    }

    private func reserve(packageCount: Int) {
        guard !isReserving else { return }
        isReserving = true
        Task {
            defer { isReserving = false }
            do {
                try await store.reserve(listing, packageCount: packageCount, dropOff: nil)
            } catch ReserveError.expired {
                reserveError = String(localized: "This listing has expired.")
            } catch {
                reserveError = error.localizedDescription
            }
        }
    }

    private var reservedByOtherControls: some View {
        VStack(spacing: Theme.Spacing.md) {
            statusNote("This food is currently reserved by someone else.")
            Button {
                store.joinWaitlist(listing)
            } label: {
                Label("Notify me if available", systemImage: "bell.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func statusNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.subheadlineMedium)
            .foregroundStyle(Theme.Palette.mutedText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Theme.Spacing.sm)
    }

    // helpers

    private var handoffMethodText: String {
        if listing.isDropOff, let radius = listing.dropOffRadiusLabel {
            return String(localized: "Drop off within \(radius)")
        }
        return listing.pickupType.displayName
    }

    private var pickupLine: String {
        if let distance = location.distanceText(to: listing.coordinate) {
            return String(localized: "\(listing.pickupAddress)\n\(distance) away")
        }
        return listing.pickupAddress
    }

    private var claimedByMe: Bool {
        session.matches(listing.claimedByDeviceID)
    }

    private var isMine: Bool {
        session.matches(listing.postedByDeviceID)
    }

    private var canSeeExact: Bool {
        if isMine { return true }
        let status = listing.effectiveStatus
        return claimedByMe && (status == .reserved || status == .readyForPickup || status == .pickedUp)
    }

    private var publicPickupSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let spot = listing.publishedPickupInstructions.handoffSpot {
                infoRow(icon: spot.symbol, title: "Handoff", value: spot.displayName)
            }
            if let timeslot = listing.publishedPickupInstructions.timeslot {
                infoRow(icon: "clock", title: "Ready by", value: timeslot.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(height: 1)
    }

    // same layout for notes that can be translated
    // uses on device translation for free text
    private func translatableInfoRow(icon: String, title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(Theme.Palette.mutedText)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                TranslatableText(text: value, font: AppFont.body, color: Theme.Palette.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoRow(icon: String, title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(Theme.Palette.mutedText)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                Text(value)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
