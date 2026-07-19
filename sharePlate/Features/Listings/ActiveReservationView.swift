//
//  ActiveReservationView.swift
//  sharePlate
//
//  Active pickup handoff — instructions are set when food is posted.
//

import SwiftUI

struct ActiveReservationView: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session
    @Environment(\.dismiss) private var dismiss

    @Bindable var listing: FoodListing

    @State private var showCancelConfirm = false
    @State private var showConsumerCancelConfirm = false
    @State private var cancelError: String?
    @State private var isCancelling = false

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
        .confirmationDialog("Cancel this reservation?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Cancel reservation", role: .destructive) {
                Task { await cancelReservation() }
            }
            Button("Keep reservation", role: .cancel) {}
        } message: {
            Text("The listing will become available again for others.")
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
            return isOwner ? "Active drop off" : "Your drop off"
        }
        return isOwner ? "Active pickup" : "Your pickup"
    }

    // MARK: - Header

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(isOwner
                 ? (listing.isDropOff ? "Someone reserved your drop off" : "Someone reserved your food")
                 : "\(listing.packagesLabel) reserved")
                .font(AppFont.title2)
                .foregroundStyle(Theme.Palette.primaryText)
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
                instructionLine(number: 4, title: "Note", value: instructions.providerNote)
            } else if let notes = listing.pickupNotes, !notes.isEmpty {
                instructionLine(number: 4, title: "Note", value: notes)
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
                instructionLine(number: 1, title: "Drop off at", value: "Waiting for address…")
            }

            instructionLine(number: 2, title: "Ready by", value: timeslotText)
            instructionLine(number: 3, title: "Handoff", value: instructions.handoffSpot?.displayName ?? "—")

            if let radius = listing.dropOffRadiusLabel {
                instructionLine(number: 4, title: "Travel radius", value: "Within \(radius) of near \(listing.areaLabel)")
            }

            if !instructions.providerNote.isEmpty {
                instructionLine(number: 5, title: "Note", value: instructions.providerNote)
            } else if let notes = listing.pickupNotes, !notes.isEmpty {
                instructionLine(number: 5, title: "Note", value: notes)
            }
        }
        .cardStyle()
    }

    // MARK: - Actions

    private var providerActions: some View {
        VStack(spacing: Theme.Spacing.md) {
            cancelButton
            CompleteHandoffButton(listing: listing)
        }
    }

    private var consumerActions: some View {
        VStack(spacing: Theme.Spacing.md) {
            releaseButton
            CompleteHandoffButton(listing: listing)
        }
    }

    private func instructionLine(number: Int, title: String, value: String) -> some View {
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
                Text(value)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.primaryText)
            }
        }
    }

    private var timeslotText: String {
        guard let timeslot = instructions.timeslot else { return "—" }
        return timeslot.formatted(date: .abbreviated, time: .shortened)
    }

    private var cancelButton: some View {
        Button {
            showCancelConfirm = true
        } label: {
            cancelLabel("CANCEL RESERVATION")
        }
        .buttonStyle(.plain)
        .disabled(isCancelling)
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

    private func cancelLabel(_ title: String) -> some View {
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
                Text(listing.isDropOff ? "Drop off" : "Pickup")
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

    private var handoffCountdownPrefix: String {
        if let timeslot = instructions.timeslot, timeslot > Date() {
            return listing.isDropOff && isOwner ? "Deliver by " : "Arrive in "
        }
        if let until = listing.reservedUntil, listing.reservationActive, until > Date() {
            return "Hold expires in "
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
    }
}
