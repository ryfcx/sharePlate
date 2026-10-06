//
//  TranslatableText.swift
//  sharePlate
//
//  On-device translation for pantry About text, hours, and neighbor-written notes.
//  The system translation sheet is used so this works in English, Spanish,
//  or the device language. It does not depend on the in-app language being Spanish.
//

import SwiftUI
import Translation

struct TranslatableText: View {
    enum Style {
        /// Text with a Translate / Show original button underneath.
        case labeled
        /// Text with a small translate icon beside it, for tight rows.
        case icon
    }

    let text: String
    var font: Font = AppFont.body
    var color: Color = Theme.Palette.primaryText
    var lineLimit: Int? = nil
    var style: Style = .labeled

    @State private var translatedText: String?
    @State private var showTranslation = false

    private var shownText: String { translatedText ?? text }

    private var isShowingTranslation: Bool {
        guard let translatedText, !translatedText.isEmpty else { return false }
        return translatedText != text
    }

    /// Skip codes, phone numbers, and placeholders that have no words.
    private var canTranslate: Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    var body: some View {
        Group {
            switch style {
            case .labeled:
                labeledBody
            case .icon:
                iconBody
            }
        }
        .onChange(of: text) {
            translatedText = nil
            showTranslation = false
        }
        .translationPresentation(isPresented: $showTranslation, text: text) { translated in
            let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            translatedText = trimmed
        }
    }

    private var labeledBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shownText)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: lineLimit == nil)

            if canTranslate {
                labeledControl
            }
        }
    }

    private var iconBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(shownText)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(lineLimit)
                .frame(maxWidth: lineLimit == nil ? nil : .infinity, alignment: .leading)

            if canTranslate {
                iconControl
            }
        }
    }

    private var labeledControl: some View {
        Button {
            if isShowingTranslation {
                translatedText = nil
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

    private var iconControl: some View {
        Image(systemName: isShowingTranslation ? "arrow.uturn.backward" : "translate")
            .font(AppFont.caption)
            .foregroundStyle(Theme.Palette.primaryGreen)
            .padding(4)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded {
                if isShowingTranslation {
                    translatedText = nil
                } else {
                    showTranslation = true
                }
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(isShowingTranslation ? "Show original" : "Translate"))
            .accessibilityAction {
                if isShowingTranslation {
                    translatedText = nil
                } else {
                    showTranslation = true
                }
            }
    }
}
