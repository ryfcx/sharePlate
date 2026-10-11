//
// resourcedetailview.swift
// shareplate
//

import SwiftUI
import SwiftData
import MapKit
import Translation

struct ResourceDetailView: View {
    @Environment(LocationManager.self) private var location
    @Query(sort: \FoodListing.createdAt, order: .reverse) private var allListings: [FoodListing]
    let resource: FoodResource

    @State private var showMiniMap = false

    private var pantryListings: [FoodListing] {
        guard let locationID = resource.gcfdLocationID else { return [] }
        return allListings.filter {
            $0.pantryGCFDLocationID == locationID && !$0.isPermanent && $0.effectiveStatus == .available
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                miniMap

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        TypeBadge(type: resource.type)
                        if resource.managedByUserID != nil {
                            Label("Volunteer-managed", systemImage: "checkmark.seal.fill")
                                .font(AppFont.caption)
                                .foregroundStyle(Theme.Palette.primaryGreen)
                        }
                    }
                    Text(resource.name)
                        .font(AppFont.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                    if let distance = location.distanceText(to: resource.coordinate) {
                        Label("\(distance) away", systemImage: "location.fill")
                            .font(AppFont.subheadlineMedium)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                }

                if resource.isTemporarilyClosed {
                    closedBanner
                }

                DirectionsButton(coordinate: resource.coordinate, name: resource.name, address: resource.address)

                if !pantryListings.isEmpty {
                    pantryListingsSection
                }

                VStack(spacing: Theme.Spacing.lg) {
                    infoRow(icon: "mappin.and.ellipse", title: "Address", value: resource.address)
                    divider
                    hoursSection
                    if let phone = resource.phone {
                        divider
                        Button {
                            call(phone)
                        } label: {
                            infoRow(icon: "phone.fill", title: "Phone", value: phone, isLink: true)
                        }
                        .buttonStyle(.plain)
                    }
                    divider
                    infoRow(icon: "info.circle", title: "About", value: resource.summary, translate: true)
                }
                .cardStyle()
            }
            .padding(Theme.Spacing.lg)
        }
        .screenBackground()
        .navigationTitle(resource.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                showMiniMap = true
            }
        }
    }

    private var closedBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.urgentRed)
            VStack(alignment: .leading, spacing: 2) {
                Text("Temporarily closed")
                    .font(AppFont.subheadlineMedium)
                    .foregroundStyle(Theme.Palette.primaryText)
                if let note = resource.pantryClosedNote, !note.isEmpty {
                    TranslatableText(text: note, font: AppFont.caption, color: Theme.Palette.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.urgentRed.opacity(0.1))
        .boxBorder(Theme.Palette.urgentRed.opacity(0.3))
    }

    private var pantryListingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Surplus food from this pantry")
                .font(AppFont.headline)
                .foregroundStyle(Theme.Palette.primaryText)
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(pantryListings) { listing in
                    NavigationLink(value: LocationDetail.listing(listing.persistentModelID)) {
                        ListingCard(listing: listing, distanceText: location.distanceText(to: listing.coordinate))
                    }
                    .buttonStyle(PlainRowButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var hoursSection: some View {
        if resource.serviceHours.isEmpty {
            infoRow(icon: "clock", title: "Hours", value: resource.hours, translate: true)
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(Theme.Palette.mutedText)

                ServiceHoursBlock(services: resource.serviceHours)

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var miniMap: some View {
        if showMiniMap {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: resource.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker(resource.name, systemImage: resource.type.symbol, coordinate: resource.coordinate)
                    .tint(resource.type.tint)
            }
            .frame(height: 180)
            .boxBorder()
            .allowsHitTesting(false)
        } else {
            Rectangle()
                .fill(Theme.Palette.softFill)
                .frame(height: 180)
                .boxBorder()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(height: 1)
    }

    private func infoRow(icon: String, title: LocalizedStringKey, value: String, isLink: Bool = false, translate: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(isLink ? Theme.Palette.primaryGreen : Theme.Palette.mutedText)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                if translate {
                    TranslatableText(
                        text: value,
                        font: AppFont.body,
                        color: isLink ? Theme.Palette.primaryGreen : Theme.Palette.primaryText
                    )
                } else {
                    Text(value)
                        .font(AppFont.body)
                        .foregroundStyle(isLink ? Theme.Palette.primaryGreen : Theme.Palette.primaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber }
        if let url = URL(string: "tel://\(digits)") {
            UIApplication.shared.open(url)
        }
    }
}

// one translate button for pantry hours
private struct ServiceHoursBlock: View {
    let services: [ServiceHours]

    private struct Piece {
        let id: String
        let text: String
    }

    @State private var translated: [String: String] = [:]
    @State private var fallbackText: String?
    @State private var isShowingTranslation = false
    @State private var showTranslation = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Hours")
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)

            if isShowingTranslation, let fallbackText {
                Text(fallbackText)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(services.enumerated()), id: \.offset) { serviceIndex, service in
                    serviceBlock(serviceIndex, service)
                }
            }

            if canTranslate {
                Button {
                    if isShowingTranslation {
                        isShowingTranslation = false
                    } else {
                        showTranslation = true
                    }
                } label: {
                    Label(
                        isShowingTranslation ? "Show original" : "Translate",
                        systemImage: isShowingTranslation ? "arrow.uturn.backward" : "translate"
                    )
                }
                .font(AppFont.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.primaryGreen)
            }
        }
        .onChange(of: combinedText) {
            translated = [:]
            fallbackText = nil
            isShowingTranslation = false
            showTranslation = false
        }
        .translationPresentation(isPresented: $showTranslation, text: combinedText) { translatedText in
            let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let mapped = Self.mappedLines(pieces: pieces, translated: trimmed) {
                translated = mapped
                fallbackText = nil
            } else {
                translated = [:]
                fallbackText = trimmed
            }
            isShowingTranslation = true
        }
    }

    private func serviceBlock(_ serviceIndex: Int, _ service: ServiceHours) -> some View {
        let lines = service.displayLines()
        return VStack(alignment: .leading, spacing: 4) {
            Text(shown("name-\(serviceIndex)", service.serviceName))
                .font(AppFont.subheadlineMedium)
                .foregroundStyle(Theme.Palette.primaryText)

            if lines.isEmpty {
                Text(shown("line-\(serviceIndex)-0", String(localized: "Call for hours")))
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.mutedText)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                    Text(shown("line-\(serviceIndex)-\(lineIndex)", line))
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        for (serviceIndex, service) in services.enumerated() {
            result.append(Piece(id: "name-\(serviceIndex)", text: service.serviceName))
            let lines = service.displayLines()
            if lines.isEmpty {
                result.append(Piece(id: "line-\(serviceIndex)-0", text: String(localized: "Call for hours")))
            } else {
                for (lineIndex, line) in lines.enumerated() {
                    result.append(Piece(id: "line-\(serviceIndex)-\(lineIndex)", text: line))
                }
            }
        }
        return result
    }

    private var combinedText: String {
        pieces.map(\.text).joined(separator: "\n")
    }

    private var canTranslate: Bool {
        combinedText.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    // puts translation back on each hour line
    private static func mappedLines(pieces: [Piece], translated: String) -> [String: String]? {
        let parts = translated.components(separatedBy: "\n")
        guard parts.count == pieces.count else { return nil }
        var next: [String: String] = [:]
        for (piece, part) in zip(pieces, parts) {
            let line = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            next[piece.id] = line
        }
        return next
    }

    private func shown(_ id: String, _ original: String) -> String {
        guard isShowingTranslation, let translated = translated[id], !translated.isEmpty else {
            return original
        }
        return translated
    }
}
