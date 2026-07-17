import SwiftUI

struct SignedInView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var container: AppContainer

    var body: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("signedIn.title", comment: ""))
                .font(.title2.bold())

            if let email = session.cachedEmail {
                Text(String(format: NSLocalizedString("signedIn.email", comment: ""), email))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(NSLocalizedString("signedIn.placeholder", comment: ""))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Button(role: .destructive) {
                Task { await container.authService.logout() }
            } label: {
                Text(NSLocalizedString("signedIn.logout", comment: ""))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .padding()
            .accessibilityIdentifier("SignedInLogout")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
    }
}