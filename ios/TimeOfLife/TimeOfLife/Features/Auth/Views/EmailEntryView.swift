import SwiftUI

/// Email entry screen for passwordless authentication.
///
/// The user enters their email address and taps "Continue" to receive a
/// one-time passcode. Validation is performed locally before the network
/// request. Follows U1 minimalistic design with Theme semantic colors.
struct EmailEntryView: View {
    @ObservedObject var vm: EmailEntryViewModel
    @EnvironmentObject var navigation: AppNavigationStack
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        VStack(spacing: Theme.spacingLarge) {
            Spacer()

            Text(L10n.authWelcome.text)
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(L10n.authSubtitle.text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: Theme.spacingSmall)

            TextFieldWithError(
                title: L10n.emailEntryEmail.text,
                placeholder: L10n.emailEntryEmail.text,
                text: $vm.email,
                error: vm.fieldErrors.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                submitLabel: .continue,
                autocapitalization: .none,
                accessibilityId: "EmailField",
                onSubmit: submit
            )
            .focused($isEmailFocused)

            if let errorMessage = vm.errorMessage {
                ErrorBanner(
                    message: errorMessage,
                    accessibilityId: "EmailErrorBanner"
                )
            }

            Spacer()
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            // Pinned action bar. Content in `safeAreaInset` animates with the
            // system keyboard transition instead of reflowing with the main
            // stack, and stays visible above the keyboard so the user can tap
            // Continue without dismissing the keyboard first.
            VStack(spacing: Theme.spacingSmall) {
                PrimaryButton(
                    title: L10n.emailEntrySubmit.text,
                    icon: nil,
                    isLoading: vm.isLoading,
                    isDisabled: vm.email.trimmingCharacters(in: .whitespaces).isEmpty,
                    accessibilityId: "EmailContinueButton",
                    action: submit
                )

                AppleSignInButton {
                    isEmailFocused = false
                    Task { await vm.signInWithApple() }
                }
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.vertical, Theme.spacingSmall)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(Theme.backgroundPrimary)
        }
        .onAppear { isEmailFocused = true }
        .onChange(of: vm.email) { _ in
            if vm.fieldErrors.email != nil {
                vm.fieldErrors.email = nil
            }
        }
        .onChange(of: vm.isEmailSent) { sent in
            if sent {
                navigation.push(.otpEntry(email: vm.email))
                vm.isEmailSent = false
            }
        }
    }

    private func submit() {
        isEmailFocused = false
        Task { await vm.submit() }
    }
}

#if DEBUG
#Preview("Email Entry — EN Light") {
    let container = AppContainer.production()
    EmailEntryView(vm: EmailEntryViewModel(
        service: container.authService,
        connectivity: container.connectivity
    ))
    .environmentObject(container.navigation)
    .environmentObject(container)
}

#Preview("Email Entry — RU Dark") {
    let container = AppContainer.production()
    EmailEntryView(vm: EmailEntryViewModel(
        service: container.authService,
        connectivity: container.connectivity
    ))
    .environmentObject(container.navigation)
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
