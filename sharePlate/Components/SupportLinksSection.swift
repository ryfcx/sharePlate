import SwiftUI

struct SupportLinksSection: View {
    let privacyPolicyURL: URL
    let supportURL: URL
    var termsURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Help & privacy")
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            VStack(spacing: 0) {
                link("Privacy policy", symbol: "hand.raised", destination: privacyPolicyURL)
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)
                link("Support", symbol: "questionmark.circle", destination: supportURL)
                if let termsURL {
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(height: 1)
                    link("Terms and conditions", symbol: "doc.text", destination: termsURL)
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private func link(_ title: LocalizedStringKey, symbol: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: Theme.Spacing.md) {
                Label(title, systemImage: symbol)
                    .font(AppFont.body)
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "arrow.up.right")
                    .font(AppFont.caption)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.Palette.primaryText)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in your browser")
    }
}
