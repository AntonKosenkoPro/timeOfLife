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
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        // `GeometryReader` + `ScrollView` gives us keyboard avoidance on
        // iOS 15. The form stacks from the top with a fixed reserve for the
        // pinned bottom action bar so the field never crowds the buttons on
        // short screens (iPhone SE 1st gen), especially while the keyboard is
        // open. A top Spacer with a minimum length keeps the form roughly
        // centered on tall screens.
        GeometryReader { _ in
            ScrollView {
                VStack(spacing: Theme.spacingLarge) {
                    Text(L10n.otpTitle.text)
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(String(format: L10n.otpSentTo.text, vm.email))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

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

                    // Extra breathing room between the input/error and the
                    // pinned bottom action bar. This space is part of the
                    // scrollable content, so when the keyboard scrolls the
                    // field into view it leaves a comfortable gap above the
                    // Verify/Resend bar on short screens (iPhone SE 1st gen).
                    Spacer().frame(height: Theme.spacingLarge)

                    // Fixed reserve for the pinned bottom action bar plus
                    // margin so the scrollable content ends well above the
                    // buttons on every screen size, even with the keyboard up.
                    Color.clear.frame(height: bottomBarHeight + Theme.spacingLarge)
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.top, Theme.spacingExtraLarge)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            // Pinned action bar so Verify/Resend animate smoothly with the
            // keyboard and remain reachable while typing. On iOS 15 the
            // enclosing `ScrollView` now makes this inset lift above the
            // keyboard (it was covered on iPhone SE 1st gen).
            MeasuredBottomBar {
                VStack(spacing: Theme.spacingSmall) {
                    // This spacer makes the action bar taller, which in turn
                    // increases the ScrollView's bottom safe-area inset and
                    // keeps the Code field from crowding the Verify/Resend
                    // bar on small screens with the keyboard open.
                    Spacer().frame(height: Theme.spacingLarge)

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
                        Text(resendLabel)
                            .font(.subheadline)
                            .foregroundStyle(resendColor)
                    }
                    .disabled(vm.isLoading || vm.resendCountdown > 0)
                    .accessibilityIdentifier("OtpResendButton")
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.vertical, Theme.spacingSmall)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
                .background(Theme.backgroundPrimary)
            }
        }
        .onPreferenceChange(BottomBarHeightPreferenceKey.self) { bottomBarHeight = $0 }
        .onAppear {
            // The OTP was already requested by the email form before this
            // screen appeared, so arm the resend cooldown immediately — the
            // Resend button must be disabled from the first appearance, not
            // only after a manual resend.
            vm.armInitialResendCooldown()
            isCodeFocused = true
        }
        .onChange(of: vm.code) { _ in
            // Only clear stale validation state per keystroke; the user taps
            // Verify to submit.
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
    }

    private func submit() {
        isCodeFocused = false
        Task { await vm.submit() }
    }

    /// Label for the Resend button: shows the plain call-to-action while it is
    /// tappable, and a live countdown while the client-side cooldown is active.
    private var resendLabel: String {
        if vm.resendCountdown > 0 {
            return String(format: L10n.otpResendCountdown.text, vm.resendCountdown)
        }
        return L10n.otpResend.text
    }

    /// Dimmed appearance while the cooldown disables the button.
    private var resendColor: Color {
        vm.resendCountdown > 0
            ? Theme.color(Theme.accentPrimary, alpha: 0.5)
            : Theme.accentPrimary
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
