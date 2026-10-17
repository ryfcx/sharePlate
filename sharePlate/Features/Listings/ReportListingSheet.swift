import SwiftUI

struct ReportListingSheet: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let listing: FoodListing
    let onSubmitted: () -> Void
    @State private var selectedReason: ReportReason?
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var notesLength: Int { notes.unicodeScalars.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(listing.title)
                        .font(AppFont.headline)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text("Why are you reporting this listing?")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.Palette.primaryText)

                    VStack(spacing: 0) {
                        ForEach(ReportReason.allCases) { reason in
                            Button { selectedReason = reason } label: {
                                HStack {
                                    Text(reason.displayName).font(AppFont.body)
                                    Spacer()
                                    Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Theme.Palette.primaryGreen)
                                }
                                .foregroundStyle(Theme.Palette.primaryText)
                                .padding(.horizontal, Theme.Spacing.lg)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedReason == reason ? .isSelected : [])
                            if reason != ReportReason.allCases.last {
                                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                            }
                        }
                    }
                    .cardStyle(padding: 0)
                    .disabled(isSubmitting)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Details (optional)").font(AppFont.headline)
                        TextField("Tell us what happened. Don't include private contact details.", text: $notes, axis: .vertical)
                            .font(AppFont.body)
                            .lineLimit(4...8)
                            .padding(12)
                            .background(Theme.Palette.cardBackground)
                            .boxBorder()
                            .disabled(isSubmitting)
                        Text("\(notesLength)/1,000 characters")
                            .font(AppFont.caption)
                            .foregroundStyle(notesLength > 1_000 ? Theme.Palette.urgentRed : Theme.Palette.mutedText)
                    }
                    .foregroundStyle(Theme.Palette.primaryText)

                    Button { Task { await submit() } } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(isSubmitting ? String(localized: "Sending report…") : String(localized: "Send report"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: selectedReason == nil || notesLength > 1_000
                        ? Theme.Palette.mutedText : Theme.Palette.primaryGreen))
                    .disabled(selectedReason == nil || notesLength > 1_000 || isSubmitting)

                    Text("Reports are reviewed by the SharePlate team. The listing provider cannot see who reported them.")
                        .font(AppFont.caption)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
                .padding(Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Report listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .alert("Couldn't send report", isPresented: Binding(
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
        guard let selectedReason, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await store.report(listing, reason: selectedReason, notes: notes)
            onSubmitted()
        } catch let error as ReportSubmissionError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = String(localized: "Your report wasn't sent. Check your connection and try again.")
        }
    }
}
