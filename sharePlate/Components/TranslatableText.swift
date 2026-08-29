//
//  TranslatableText.swift
//  sharePlate
//
//  On-device translation (Apple's Translation framework) for free-text a
//  user typed themselves — listing titles, pickup/drop-off notes. These
//  can't go through the String Catalog since the app doesn't know their
//  content in advance. Translation is opt-in per piece of text (a tap),
//  never automatic — the app shouldn't silently rewrite what someone wrote.
//

import SwiftUI
import Translation

struct TranslatableText: View {
    let text: String
    var font: Font = AppFont.body
    var color: Color = Theme.Palette.primaryText

    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue
    @State private var translatedText: String?
    @State private var isTranslating = false
    @State private var translationFailed = false
    @State private var configuration: TranslationSession.Configuration?

    /// Only offer translation when the app's language is explicitly set
    /// (not "System") — otherwise "translate to what?" is ambiguous.
    private var targetLanguage: AppLanguage? {
        let language = AppLanguage(rawValue: appLanguageRaw) ?? .system
        return language == .system ? nil : language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(translatedText ?? text)
                .font(font)
                .foregroundStyle(color)

            if let targetLanguage {
                translateControl(target: targetLanguage)
            }
        }
        .translationTask(configuration) { session in
            isTranslating = true
            translationFailed = false
            defer { isTranslating = false }
            do {
                let response = try await session.translate(text)
                translatedText = response.targetText
            } catch {
                translationFailed = true
            }
            configuration = nil
        }
    }

    @ViewBuilder
    private func translateControl(target: AppLanguage) -> some View {
        if isTranslating {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Translating…")
            }
            .font(AppFont.caption)
            .foregroundStyle(Theme.Palette.mutedText)
        } else if let translatedText, !translatedText.isEmpty {
            Button {
                self.translatedText = nil
            } label: {
                Label("Show original", systemImage: "arrow.uturn.backward")
            }
            .font(AppFont.caption)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.primaryGreen)
        } else {
            Button {
                configuration = TranslationSession.Configuration(target: target.locale.language)
            } label: {
                Label("Translate", systemImage: "translate")
            }
            .font(AppFont.caption)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.primaryGreen)

            if translationFailed {
                Text("Couldn't translate")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
            }
        }
    }
}
