//
//  AuthView.swift
//  sharePlate
//
//  Required sign-in / sign-up gate. Flat, boxy styling to match the app.
//

import SwiftUI

struct AuthView: View {
    @Environment(SupabaseAuthService.self) private var auth

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

    private var isSignUp: Bool { mode == .signUp }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                VStack(spacing: Theme.Spacing.md) {
                    if isSignUp {
                        field("Name", text: $name, prompt: "Your name", content: .name)
                    }
                    field("Email", text: $email, prompt: "you@example.com", content: .emailAddress, keyboard: .emailAddress)
                    secureField("Password", text: $password, prompt: isSignUp ? "At least 6 characters" : "Your password")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.subheadlineMedium)
                        .foregroundStyle(Theme.Palette.urgentRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    submit()
                } label: {
                    Text(isSignUp ? "Create Account" : "Sign In")
                }
                .buttonStyle(PrimaryButtonStyle())

                toggleRow
            }
            .padding(Theme.Spacing.lg)
        }
        .screenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("SharePlate")
                .font(AppFont.largeTitle)
                .foregroundStyle(Theme.Palette.primaryGreen)
            Text(isSignUp
                 ? "Create an account to share and find free food nearby."
                 : "Sign in to share and find free food nearby.")
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.mutedText)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private var toggleRow: some View {
        HStack(spacing: 4) {
            Text(isSignUp ? "Already have an account?" : "New to SharePlate?")
                .font(AppFont.subheadline)
                .foregroundStyle(Theme.Palette.mutedText)
            Button {
                withAnimation(.none) {
                    mode = isSignUp ? .signIn : .signUp
                    errorMessage = nil
                }
            } label: {
                Text(isSignUp ? "Sign in" : "Create one")
                    .font(AppFont.subheadlineMedium)
                    .foregroundStyle(Theme.Palette.primaryGreen)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, content: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
            TextField(prompt, text: text)
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .textContentType(content)
                .keyboardType(keyboard)
                .textInputAutocapitalization(label == "Name" ? .words : .never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.Palette.cardBackground)
                .boxBorder()
        }
    }

    private func secureField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
            SecureField(prompt, text: text)
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .textContentType(isSignUp ? .newPassword : .password)
                .padding(12)
                .background(Theme.Palette.cardBackground)
                .boxBorder()
        }
    }

    private func submit() {
        errorMessage = nil
        Task {
            do {
                if isSignUp {
                    try await auth.signUp(name: name, email: email, password: password)
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
