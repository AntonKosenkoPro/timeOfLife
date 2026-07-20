import SwiftUI

struct SignedInView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var container: AppContainer

    var body: some View {
        VStack(spacing: Theme.spacingMedium) {
            Text(L10n.signedInTitle.text)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            if let email = session.cachedEmail {
                Text(String(format: L10n.signedInEmail.text, email))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(L10n.signedInPlaceholder.text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            PrimaryButton(
                title: L10n.signedInLogout.text,
                icon: nil,
                isLoading: false,
                isDisabled: false,
                accessibilityId: "SignedInLogout"
            ) {
                Task { await container.authService.logout() }
            }
            .tint(Theme.danger)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
    }
}

#if DEBUG
#Preview("Signed In — EN Light") {
    let container = AppContainer.production()
    SignedInView()
        .environmentObject(container.sessionStore)
        .environmentObject(container)
}

#Preview("Signed In — RU Dark") {
    let container = AppContainer.production()
    SignedInView()
        .environmentObject(container.sessionStore)
        .environmentObject(container)
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}
#endif
