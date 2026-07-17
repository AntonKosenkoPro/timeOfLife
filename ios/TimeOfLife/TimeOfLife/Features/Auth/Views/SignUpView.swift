import SwiftUI

struct SignUpView: View {
    @ObservedObject var vm: SignUpViewModel

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("signup.email", comment: ""), text: $vm.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("SignUpEmail")
                SecureField(NSLocalizedString("signup.password", comment: ""), text: $vm.password)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("SignUpPassword")
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
                        Text(NSLocalizedString("signup.submit", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.isSubmitting || vm.isOffline)
                .accessibilityIdentifier("SignUpSubmit")
            }
            if let success = vm.successMessage {
                Section { Text(success).foregroundStyle(Theme.success) }
                    .accessibilityIdentifier("SignUpSuccess")
            }
            if let error = vm.submitError {
                Section { Text(error).foregroundStyle(Theme.danger) }
                    .accessibilityIdentifier("SignUpSubmitError")
            }
        }
        .navigationTitle(NSLocalizedString("signup.title", comment: ""))
    }
}