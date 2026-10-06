//
//  SearchBox.swift
//  sharePlate
//

import SwiftUI

struct SearchBox: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.mutedText)
            TextField(text: $text, prompt: Text(LocalizedStringKey(prompt))) {
                EmptyView()
            }
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.mutedText.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Palette.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .boxBorder(radius: Theme.Radius.control)
    }
}
