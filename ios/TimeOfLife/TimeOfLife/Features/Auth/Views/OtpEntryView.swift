import SwiftUI

/// OTP entry screen for passwordless authentication.
///
/// The user enters the 6-digit code sent to their email in a one-box-per-digit
/// field (`OtpCodeField`). The code auto-submits ~250 ms after the 6th digit is
/// entered so the user sees the complete code before the network call. On a
/// verification failure the code is cleared so the user can re-type. Follows
/// U1 minimalistic design with Theme semantic colors.
struct OtpEntryView: View {
    @ObservedObject var vm: OtpEntryViewModel
    @EnvironmentObject var navigation: AppNavigationStack
    @EnvironmentObject var container: AppContainer
    @State private var bottomBarHeight: CGFloat = 0
    @State private var autoSubmitTask: Task<Void, Never>?

    var body: some View {
        // `GeometryReader` + `ScrollView` gives us keyboard avoidance on
        // iOS 15. The form stacks from the top with a fixed reserve for the
        // pinned bottom action bar so the field never crowds the buttons on
        // short screens (iPhone SE 1st gen), especially while the keyboard is
        // open. Content scrolls when it does not fit.
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

                    OtpCodeField(
                        code: $vm.code,
                        length: 6,
                        error: vm.fieldErrors.otp,
                        isLoading: vm.isLoading,
                        accessibilityId: "OtpCodeField"
                    )

                    if let errorMessage = vm.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            accessibilityId: "OtpErrorBanner"
                        )
                    }

                    // Extra breathing room between the field/error and the
                    // pinned bottom action bar. This space is part of the
                    // scrollable content, so when the keyboard scrolls the
                    // field into view it leaves a comfortable gap above the
                    // Resend/Change-email bar on short screens (iPhone SE 1st gen).
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
            // Pinned action bar so Resend/Change-email animate smoothly with
            // the keyboard and remain reachable while typing. On iOS 15 the
            // enclosing `ScrollView` now makes this inset lift above the
            // keyboard (it was covered on iPhone SE 1st gen).
            MeasuredBottomBar {
                VStack(spacing: Theme.spacingSmall) {
                    // This spacer makes the action bar taller, which in turn
                    // increases the ScrollView's bottom safe-area inset and
                    // keeps the Code field from crowding the bar on small
                    // screens with the keyboard open.
                    Spacer().frame(height: Theme.spacingLarge)

                    Button {
                        Task { await vm.resendOtp() }
                    } label: {
                        Text(resendLabel)
                            .font(.subheadline)
                            .foregroundStyle(resendColor)
                    }
                    .disabled(vm.isLoading || vm.resendCountdown > 0 || !container.connectivity.isConnected)
                    .accessibilityIdentifier("OtpResendButton")

                    Button {
                        navigation.popLast()
                    } label: {
                        Text(L10n.otpChangeEmail.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityIdentifier("OtpChangeEmailButton")
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
        }
        .onChange(of: vm.code) { newValue in
            // Clear stale validation state per keystroke.
            if vm.fieldErrors.otp != nil {
                vm.fieldErrors.otp = nil
            }

            // Auto-submit after the 6th digit, debounced so the user sees the
            // full code before the network call. A shorter/changed code cancels
            // any pending auto-submit. The field stays first responder (we do
            // not dismiss the keyboard); on success `AuthService` flips
            // `SessionStore` and `RootView` swaps to `TimerView`.
            autoSubmitTask?.cancel()
            guard newValue.count == 6 else { return }
            autoSubmitTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, vm.code.count == 6, !vm.isLoading else { return }
                await vm.submit()
            }
        }
        .onDisappear {
            autoSubmitTask?.cancel()
        }
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
