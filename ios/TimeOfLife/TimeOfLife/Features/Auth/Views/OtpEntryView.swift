import SwiftUI

/// OTP entry screen for passwordless authentication.
///
/// The user enters the 6-digit code sent to their email. Supports magic-link
/// deep link pre-fill and auto-submit. Follows U1 minimalistic design with
/// Theme semantic colors.
struct OtpEntryView: View {
    @ObservedObject var vm: OtpEntryViewModel
    @EnvironmentObject var navigation: AppNavigationStack
    @FocusState private var isCodeFocused: Bool

    /// The deep link code to pre-fill, consumed on appear.
    @State private var consumedDeepLink = false

    var body: some View {
        VStack(spacing: Theme.spacingLarge) {
            Spacer()

            Text(L10n.otpTitle.text)
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(String(format: L10n.otpSentTo.text, vm.email))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: Theme.spacingSmall)

            TextFieldWithError(
                title: L10n.otpCode.text,
                placeholder: L10n.otpCode.text,
                text: $vm.code,
                error: vm.fieldErrors.otp,
                keyboardType: .numberPad,
                textContentType: .oneTimeCode,
                submitLabel: .continue,
                autocapitalization: .none,
                accessibilityId: "OtpField",
                onSubmit: submit
            )
            .focused($isCodeFocused)

            if let errorMessage = vm.errorMessage {
                ErrorBanner(
                    message: errorMessage,
                    accessibilityId: "OtpErrorBanner"
                )
            }

            Spacer()
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            // Pinned action bar so Verify/Resend animate smoothly with the
            // keyboard and remain reachable while typing.
            VStack(spacing: Theme.spacingSmall) {
                PrimaryButton(
                    title: L10n.otpSubmit.text,
                    icon: nil,
                    isLoading: vm.isLoading,
                    isDisabled: vm.code.trimmingCharacters(in: .whitespaces).isEmpty,
                    accessibilityId: "OtpVerifyButton",
                    action: submit
                )

                Button {
                    Task { await vm.resendOtp() }
                } label: {
                    Text(L10n.otpResend.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentPrimary)
                }
                .disabled(vm.isLoading)
                .accessibilityIdentifier("OtpResendButton")
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.vertical, Theme.spacingSmall)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(Theme.backgroundPrimary)
        }
        .onAppear {
            // Consume a pending deep link before claiming focus: deep links
            // auto-submit, so we must not also focus the field (which would
            // dismiss and re-show the keyboard and race the submit).
            if let code = navigation.pendingDeepLinkCode, !consumedDeepLink {
                consumedDeepLink = true
                vm.handleDeepLinkCode(code)
                navigation.pendingDeepLinkCode = nil
            } else {
                isCodeFocused = true
            }
        }
        .onChange(of: vm.code) { _ in
            // Only clear stale validation state per keystroke. We deliberately
            // do NOT auto-submit on a 6-digit count here: doing so dismissed
            // the keyboard mid-typing and double-submitted on deep links
            // (handleDeepLinkCode already submits). The user taps Verify.
            if vm.fieldErrors.otp != nil {
                vm.fieldErrors.otp = nil
            }
        }
        .onChange(of: vm.isVerified) { verified in
            if verified {
                navigation.push(.signedIn)
                vm.isVerified = false
            }
        }
        .onChange(of: navigation.pendingDeepLinkCode) { code in
            guard let code, !consumedDeepLink else { return }
            consumedDeepLink = true
            vm.handleDeepLinkCode(code)
            navigation.pendingDeepLinkCode = nil
        }
    }

    private func submit() {
        isCodeFocused = false
        Task { await vm.submit() }
    }
}

#if DEBUG
#Preview("OTP Entry — EN Light") {
    let container = AppContainer.production()
    OtpEntryView(vm: OtpEntryViewModel(
        service: container.authService,
        connectivity: container.connectivity,
        email: "preview@example.com"
    ))
    .environmentObject(container.navigation)
    .environmentObject(container)
}

#Preview("OTP Entry — RU Dark") {
    let container = AppContainer.production()
    OtpEntryView(vm: OtpEntryViewModel(
        service: container.authService,
        connectivity: container.connectivity,
        email: "preview@example.com"
    ))
    .environmentObject(container.navigation)
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
