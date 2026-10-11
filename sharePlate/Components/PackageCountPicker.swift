//
//  packagecountpicker.swift
//  shareplate
//
//  tap based package count picker for post and reserve flows
//

import SwiftUI

struct PackageCountPicker: View {
    @Binding var selection: Int
    let range: ClosedRange<Int>
    var label: String = "packages"

    // one button per count fits short rows, bigger stocks use stepper
    private var usesStepper: Bool { range.count > 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if usesStepper {
                stepper
            } else {
                buttonRow
            }

            Text("\(selection) \(selection == 1 ? "package" : "packages") selected")
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(range), id: \.self) { count in
                Button {
                    selection = count
                } label: {
                    Text("\(count)")
                        .font(AppFont.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection == count ? Theme.Palette.primaryGreen : Theme.Palette.cardBackground)
                        .foregroundStyle(selection == count ? Color.white : Theme.Palette.primaryText)
                        .boxBorder(selection == count ? Theme.Palette.primaryGreen.opacity(0.5) : Theme.Palette.hairline)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: Theme.Spacing.md) {
            stepButton(systemImage: "minus", enabled: selection > range.lowerBound) {
                selection = max(range.lowerBound, selection - 1)
            }
            Text("\(selection)")
                .font(AppFont.title2.monospacedDigit())
                .foregroundStyle(Theme.Palette.primaryText)
                .frame(maxWidth: .infinity)
            stepButton(systemImage: "plus", enabled: selection < range.upperBound) {
                selection = min(range.upperBound, selection + 1)
            }
        }
        .padding(Theme.Spacing.sm)
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppFont.headline)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.cardBackground)
                .foregroundStyle(enabled ? Theme.Palette.primaryGreen : Theme.Palette.mutedText)
                .boxBorder()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct MaxPerBookingPicker: View {
    @Binding var selection: Int
    let totalPackages: Int

    private var options: [Int] {
        Array(1...totalPackages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(options, id: \.self) { count in
                    Button {
                        selection = count
                    } label: {
                        Text(count == totalPackages ? "All" : "\(count)")
                            .font(AppFont.footnote)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selection == count ? Theme.Palette.primaryGreen : Theme.Palette.cardBackground)
                            .foregroundStyle(selection == count ? Color.white : Theme.Palette.primaryText)
                            .boxBorder(selection == count ? Theme.Palette.primaryGreen.opacity(0.5) : Theme.Palette.hairline)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(selection >= totalPackages
                 ? "One person can take all \(totalPackages) packages"
                 : "Max \(selection) package\(selection == 1 ? "" : "s") per booking")
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }
}

struct PackageReserveSheet: View {
    @Environment(\.dismiss) private var dismiss

    let listing: FoodListing
    let onReserve: (Int) async throws -> Void

    @State private var selectedCount: Int
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(listing: FoodListing, onReserve: @escaping (Int) async throws -> Void) {
        self.listing = listing
        self.onReserve = onReserve
        let maxAllowed = min(listing.effectiveMaxPerBooking, listing.effectivePackagesRemaining)
        _selectedCount = State(initialValue: maxAllowed > 8 ? 1 : max(1, maxAllowed))
    }

    private var maxAllowed: Int {
        min(listing.effectiveMaxPerBooking, listing.effectivePackagesRemaining)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(listing.isDropOff
                         ? "How many packages should the donor bring?"
                         : "How many packages are you picking up?")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Theme.Palette.mutedText)

                    PackageCountPicker(
                        selection: $selectedCount,
                        range: 1...max(1, maxAllowed),
                        label: "packages"
                    )
                    .cardStyle(padding: 0)

                    if listing.packageCount > 0, listing.effectivePackagesRemaining < listing.packageCount {
                        Text("\(listing.effectivePackagesRemaining) of \(listing.packageCount) packages left on this listing.")
                            .font(AppFont.caption)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Choose packages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text("Reserve \(selectedCount)x")
                                .font(AppFont.button)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
                .padding(Theme.Spacing.lg)
                .background(Theme.Palette.backgroundCream)
            }
            .alert("Couldn't reserve", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func submit() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await onReserve(selectedCount)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
