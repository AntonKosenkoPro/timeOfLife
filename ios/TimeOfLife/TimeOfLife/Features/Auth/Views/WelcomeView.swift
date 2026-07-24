import SwiftUI

/// Welcome screen — the root of the signed-out flow.
///
/// Introduces the app ("Time of Life — personal time tracker") and leads with
/// Sign in with Apple as the primary, default auth method. Email/OTP is a
/// secondary option reached via a plain text button that pushes `.emailEntry`.
/// The email button is always tappable (it only navigates); it is disabled only
/// while an Apple sign-in attempt is in flight to prevent concurrent auth flows.
/// No text entry on this screen, so there is no keyboard handling.
struct WelcomeView: View {
    @ObservedObject var vm: WelcomeViewModel
    @EnvironmentObject var navigation: AppNavigationStack
    @EnvironmentObject var container: AppContainer

    private var isOffline: Bool { !container.connectivity.isConnected }
    private var appleButtonDisabled: Bool { isOffline || vm.isLoading }
    private var emailButtonDisabled: Bool { vm.isLoading }

    var body: some View {
        ScrollView {

            VStack(spacing: Theme.spacingLarge) {
                Spacer(minLength: Theme.spacingExtraLarge)

                // Decorative brand mark; hidden from VoiceOver.
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Theme.accentPrimary)
                    .accessibilityHidden(true)

                Text(L10n.appName.text)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(L10n.welcomeTagline.text)
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage = vm.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        accessibilityId: "WelcomeErrorBanner"
                    )
                }

                // Extra breathing room above the pinned bottom action bar.
                Spacer().frame(height: Theme.spacingExtraLarge)

                // Fixed reserve so the scrollable content ends above the bar.
                Color.clear.frame(height: bottomBarHeight + Theme.spacingLarge)
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            MeasuredBottomBar {
                VStack(spacing: Theme.spacingSmall) {
                    Spacer().frame(height: Theme.spacingLarge)

                    AppleSignInButton {
                        Task { await vm.signInWithApple() }
                    }
                    .disabled(appleButtonDisabled)
                    .opacity(appleButtonDisabled ? 0.6 : 1)
                    .animation(.easeInOut(duration: 0.15), value: appleButtonDisabled)
                    
                    Spacer().frame(height: Theme.spacingSmall)
                    
                    Button {
                        navigation.push(.emailEntry)
                    } label: {
                        Text(L10n.welcomeContinueWithEmail.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.minTapArea)
                    }
                    .disabled(emailButtonDisabled)
                    .accessibilityIdentifier("WelcomeContinueWithEmailButton")
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.vertical, Theme.spacingSmall)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
                .background(Theme.backgroundPrimary)
            }
        }
        .onPreferenceChange(BottomBarHeightPreferenceKey.self) { bottomBarHeight = $0 }
        .onAppear { vm.reset() }
    }

    @State private var bottomBarHeight: CGFloat = 0
}

#if DEBUG
#Preview("Welcome — EN Light") {
    let container = AppContainer.production()
    WelcomeView(vm: WelcomeViewModel(
        service: container.authService,
        connectivity: container.connectivity,
        appleService: container.appleService
    ))
    .environmentObject(container.navigation)
    .environmentObject(container)
}

#Preview("Welcome — RU Dark") {
    let container = AppContainer.production()
    WelcomeView(vm: WelcomeViewModel(
        service: container.authService,
        connectivity: container.connectivity,
        appleService: container.appleService
    ))
    .environmentObject(container.navigation)
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
