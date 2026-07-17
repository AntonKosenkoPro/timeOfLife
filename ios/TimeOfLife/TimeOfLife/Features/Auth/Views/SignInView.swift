import SwiftUI

struct SignInView: View {
    @ObservedObject var vm: SignInViewModel
    @EnvironmentObject var container: AppContainer

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("signin.email", comment: ""), text: $vm.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .accessibilityIdentifier("SignInEmail")
                SecureField(NSLocalizedString("signin.password", comment: ""), text: $vm.password)
                    .textContentType(.password)
                    .accessibilityIdentifier("SignInPassword")
            }
            if !vm.fieldErrors.email.isEmpty {
                ErrorSection(messages: vm.fieldErrors.email)
            }
            if !vm.fieldErrors.password.isEmpty {
                ErrorSection(messages: vm.fieldErrors.password)
            }
            Section {
                Button {
                    Task { await vm.submit() }
                } label: {
                    HStack {
                        if vm.isSubmitting { ProgressView() }
                        Text(NSLocalizedString("signin.submit", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.isSubmitting || vm.isOffline)
                .accessibilityIdentifier("SignInSubmit")

                RouteLink(stack: container.navigation, route: .forgotPassword) {
                    Text(NSLocalizedString("signin.forgotPassword", comment: ""))
                        .font(.footnote)
                }
                .accessibilityIdentifier("SignInForgot")
            }
            if let success = vm.successMessage {
                Section { Text(success).foregroundStyle(Theme.success) }
            }
            if let error = vm.submitError {
                Section { Text(error).foregroundStyle(Theme.danger) }
                    .accessibilityIdentifier("SignInSubmitError")
            }
        }
        .navigationTitle(NSLocalizedString("signin.title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RouteLink(stack: container.navigation, route: .signUp) {
                    Text(NSLocalizedString("signin.signUp", comment: ""))
                }
                .accessibilityIdentifier("SignInSignUp")
            }
        }
    }
}

struct ErrorSection: View {
    let messages: [String]
    var body: some View {
        Section {
            ForEach(messages, id: \.self) { Text($0).foregroundStyle(Theme.danger).font(.caption) }
        }
    }
}