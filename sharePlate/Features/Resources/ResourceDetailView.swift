//
//  ResourceDetailView.swift
//  sharePlate
//

import SwiftUI
import MapKit

struct ResourceDetailView: View {
    @Environment(LocationManager.self) private var location
    let resource: FoodResource

    @State private var showMiniMap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                miniMap

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    TypeBadge(type: resource.type)
                    Text(resource.name)
                        .font(AppFont.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                    if let distance = location.distanceText(to: resource.coordinate) {
                        Label("\(distance) away", systemImage: "location.fill")
                            .font(AppFont.subheadlineMedium)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                }

                DirectionsButton(coordinate: resource.coordinate, name: resource.name, address: resource.address)

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
                    infoRow(icon: "info.circle", title: "About", value: resource.summary)
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

    @ViewBuilder
    private var hoursSection: some View {
        if resource.serviceHours.isEmpty {
            infoRow(icon: "clock", title: "Hours", value: resource.hours)
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(Theme.Palette.mutedText)

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Hours")
                        .font(AppFont.caption)
                        .foregroundStyle(Theme.Palette.mutedText)

                    ForEach(resource.serviceHours) { service in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.serviceName)
                                .font(AppFont.subheadlineMedium)
                                .foregroundStyle(Theme.Palette.primaryText)

                            let lines = service.displayLines()
                            if lines.isEmpty {
                                Text("Call for hours")
                                    .font(AppFont.body)
                                    .foregroundStyle(Theme.Palette.mutedText)
                            } else {
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(AppFont.body)
                                        .foregroundStyle(Theme.Palette.primaryText)
                                }
                            }
                        }
                    }
                }

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

    private func infoRow(icon: String, title: String, value: String, isLink: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(isLink ? Theme.Palette.primaryGreen : Theme.Palette.mutedText)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                Text(value)
                    .font(AppFont.body)
                    .foregroundStyle(isLink ? Theme.Palette.primaryGreen : Theme.Palette.primaryText)
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
