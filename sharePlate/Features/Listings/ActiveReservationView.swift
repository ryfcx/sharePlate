//
// activereservationview.swift
// shareplate
//
// active pickup handoff with posted instructions
//

import SwiftUI

struct ActiveReservationView: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session
    @Environment(\.dismiss) private var dismiss

    @Bindable var listing: FoodListing

    @State private var showConsumerCancelConfirm = false
    @State private var cancelError: String?
    @State private var isCancelling = false
    @State private var reserverDisplayName: String?

    private var isOwner: Bool {
        session.matches(listing.postedByDeviceID)
    }

    private var instructions: ReservationCoordination {
        listing.coordination.instructionsPublished || listing.coordination.providerSetupComplete
            ? listing.coordination
            : listing.publishedPickupInstructions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if listing.revealsBookingCode {
                    BookingCodeCard(
                        code: listing.bookingCode,
                        caption: isOwner
                            ? "Match this with the neighbor."
                            : "Show this at handoff."
                    )
                }
                statusHeader
                instructionsCard
                if listing.isDropOff, isOwner, instructions.consumerDropOffComplete,
                   let coordinate = instructions.consumerDropOffCoordinate {
                    DirectionsButton(
                        coordinate: coordinate,
                        name: listing.title,
                        address: instructions.consumerDropOffAddress
                    )
                } else if !listing.isDropOff, instructions.addressStepComplete {
                    DirectionsButton(
                        coordinate: instructions.meetupCoordinate ?? listing.coordinate,
                        name: listing.title,
                        address: instructions.meetupAddress
                    )
                }
                if isOwner {
                    providerActions
                } else {
                    consumerActions
                }
                listingSummary
            }
            .padding(Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: listing.remoteID) {
            await refreshHandoffState()
        }
        .confirmationDialog("Release this reservation?", isPresented: $showConsumerCancelConfirm, titleVisibility: .visible) {
            Button("Release reservation", role: .destructive) {
                Task { await cancelReservation() }
            }
            Button("Keep reservation", role: .cancel) {}
        } message: {
            Text("You'll give up this reservation so someone else can claim it.")
        }
        .alert("Couldn't cancel reservation", isPresented: Binding(
            get: { cancelError != nil },
            set: { if !$0 { cancelError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelError ?? "")
        }
    }

    private var navigationTitle: String {
        if listing.isDropOff {
            return isOwner ? String(localized: "Active drop off") : String(localized: "Your drop off")
        }
        return isOwner ? String(localized: "Active pickup") : String(localized: "Your pickup")
    }

    // header

    private var statusHeaderTitle: String {
        if isOwner {
            return listing.isDropOff
                ? String(localized: "Someone reserved your drop off")
                : String(localized: "Someone reserved your food")
        }
        return String(localized: "\(listing.packagesLabel) reserved")
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(statusHeaderTitle)
                .font(AppFont.title2)
                .foregroundStyle(Theme.Palette.primaryText)
            if isOwner {
                Label(
                    "Reserved by \(reserverDisplayName ?? String(localized: "Neighbor"))",
                    systemImage: "person.crop.circle.fill"
                )
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.primaryGreen)

                Label(remainingPackagesText, systemImage: "shippingbox.fill")
                    .font(AppFont.subheadlineMedium)
                    .foregroundStyle(
                        listing.effectivePackagesRemaining > 0
                            ? Theme.Palette.primaryGreen
                            : Theme.Palette.mutedText
                    )
            }
            Text(isOwner
                 ? (listing.isDropOff
                    ? "Head to their address below. Send travel updates so they know when you're coming."
                    : "Pickup details were set when you posted. Send updates below if anything changes.")
                 : (listing.isDropOff
                    ? "The donor will come to your address. Send updates when you're ready."
                    : "Follow the pickup details below."))
                .font(AppFont.subheadline)
                .foregroundStyle(Theme.Palette.mutedText)

            CountdownText(deadline: handoffDeadline, prefix: handoffCountdownPrefix, suffix: "", live: true)
                .font(AppFont.headline)

            Text(listing.title)
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private var instructionsCard: some View {
        if listing.isDropOff {
            dropOffInstructionsCard
        } else {
            pickupInstructionsCard
        }
    }

    private var pickupInstructionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Pickup details")
                .font(AppFont.headline)

            instructionLine(number: 1, title: "Go to", value: instructions.meetupAddress)
            instructionLine(number: 2, title: "Arrive by", value: timeslotText)
            instructionLine(number: 3, title: "Handoff", value: instructions.handoffSpot?.displayName ?? "—")
            if !instructions.providerNote.isEmpty {
                translatableInstructionLine(number: 4, title: "Note", value: instructions.providerNote)
            } else if let notes = listing.pickupNotes, !notes.isEmpty {
                translatableInstructionLine(number: 4, title: "Note", value: notes)
            }
        }
        .cardStyle()
    }

    private var dropOffInstructionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Drop-off details")
                .font(AppFont.headline)

            if instructions.consumerDropOffComplete {
                instructionLine(number: 1, title: isOwner ? "Drop off at" : "Your address", value: instructions.consumerDropOffAddress)
            } else {
                instructionLine(
                    number: 1,
                    title: "Drop off at",
                    value: String(localized: "Waiting for address…")
                )
            }

            instructionLine(number: 2, title: "Ready by", value: timeslotText)
            instructionLine(number: 3, title: "Handoff", value: instructions.handoffSpot?.displayName ?? "—")

            if let radius = listing.dropOffRadiusLabel {
                instructionLine(
                    number: 4,
                    title: "Travel radius",
                    value: String(localized: "Within \(radius) of near \(listing.areaLabel)")
                )
            }

            if !instructions.providerNote.isEmpty {
                translatableInstructionLine(number: 5, title: "Note", value: instructions.providerNote)
            } else if let notes = listing.pickupNotes, !notes.isEmpty {
                translatableInstructionLine(number: 5, title: "Note", value: notes)
            }
        }
        .cardStyle()
    }

    // actions

    private var providerActions: some View {
        VStack(spacing: Theme.Spacing.md) {
            CompleteHandoffButton(listing: listing)
        }
    }

    private var consumerActions: some View {
        VStack(spacing: Theme.Spacing.md) {
            releaseButton
            CompleteHandoffButton(listing: listing)
        }
    }

    private func instructionLine(number: Int, title: LocalizedStringKey, value: String, translate: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text("\(number)")
                .font(AppFont.captionBold)
                .frame(width: 24, height: 24)
                .background(Theme.Palette.softFill)
                .boxBorder()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                if translate {
                    TranslatableText(text: value, font: AppFont.body, color: Theme.Palette.primaryText)
                } else {
                    Text(value)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                }
            }
        }
    }

    private func translatableInstructionLine(number: Int, title: LocalizedStringKey, value: String) -> some View {
        instructionLine(number: number, title: title, value: value, translate: true)
    }

    private var timeslotText: String {
        guard let timeslot = instructions.timeslot else { return "—" }
        return timeslot.formatted(date: .abbreviated, time: .shortened)
    }

    private var releaseButton: some View {
        Button {
            showConsumerCancelConfirm = true
        } label: {
            cancelLabel("RELEASE RESERVATION")
        }
        .buttonStyle(.plain)
        .disabled(isCancelling)
    }

    private func cancelLabel(_ title: LocalizedStringKey) -> some View {
        Group {
            if isCancelling {
                ProgressView()
            } else {
                Text(title)
                    .font(AppFont.button)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .foregroundStyle(Theme.Palette.urgentRed)
        .background(Theme.Palette.cardBackground)
        .boxBorder(Theme.Palette.urgentRed.opacity(0.45))
    }

    private var listingSummary: some View {
        HStack {
            ListingPhotoView(listing: listing, thumbnailSize: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.category.displayName)
                    .font(AppFont.headline)
                Text(listing.isDropOff ? String(localized: "Drop off") : String(localized: "Pickup"))
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
        .cardStyle()
    }

    private var handoffDeadline: Date {
        if let timeslot = instructions.timeslot, timeslot > Date() {
            return timeslot
        }
        if let until = listing.reservedUntil, listing.reservationActive, until > Date() {
            return until
        }
        return listing.pickupDeadline
    }

    private var remainingPackagesText: String {
        let remaining = listing.effectivePackagesRemaining
        if remaining == 0 {
            return String(localized: "No packages left after this handoff")
        }
        if remaining == 1 {
            return String(localized: "1 package left after this handoff")
        }
        return String(localized: "\(remaining) packages left after this handoff")
    }

    private var handoffCountdownPrefix: String {
        if let timeslot = instructions.timeslot, timeslot > Date() {
            return listing.isDropOff && isOwner
                ? String(localized: "Deliver by ")
                : String(localized: "Arrive in ")
        }
        if let until = listing.reservedUntil, listing.reservationActive, until > Date() {
            return String(localized: "Hold expires in ")
        }
        return ""
    }

    static func isActiveParticipant(_ listing: FoodListing, session: SessionContext) -> Bool {
        let status = listing.effectiveStatus
        guard status != .pickedUp, status != .expired else { return false }

        let isOwner = session.matches(listing.postedByDeviceID)
        let isClaimer = session.matches(listing.claimedByDeviceID)

        if isClaimer && (status == .reserved || status == .readyForPickup) {
            return true
        }
        if isOwner && listing.claimedByDeviceID != nil {
            return status == .reserved || status == .readyForPickup || status == .available
        }
        return false
    }

    private func cancelReservation() async {
        guard !isCancelling else { return }
        isCancelling = true
        defer { isCancelling = false }

        do {
            try await store.cancelReservation(listing)
            dismiss()
        } catch {
            cancelError = error.localizedDescription
        }
    }

    private func refreshHandoffState() async {
        await store.syncListing(listing)
        guard isOwner,
              let remoteID = listing.remoteID,
              let listingID = UUID(uuidString: remoteID) else {
            return
        }
        reserverDisplayName = await SupabaseListingService.fetchReserverDisplayName(listingID: listingID)
    }
}
