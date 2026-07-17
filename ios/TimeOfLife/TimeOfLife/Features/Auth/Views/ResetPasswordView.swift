import SwiftUI

struct ResetPasswordView: View {
    @ObservedObject var vm: ResetPasswordViewModel

    var body: some View {
        Form {
            Section {
                SecureField(NSLocalizedString("reset.password", comment: ""), text: $vm.password)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("ResetPassword")
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
                        Text(NSLocalizedString("reset.submit", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.isSubmitting || vm.isOffline)
                .accessibilityIdentifier("ResetSubmit")
            }
            if let success = vm.successMessage {
                Section { Text(success).foregroundStyle(Theme.success) }
                    .accessibilityIdentifier("ResetSuccess")
            }
            if let error = vm.submitError {
                Section { Text(error).foregroundStyle(Theme.danger) }
                    .accessibilityIdentifier("ResetSubmitError")
            }
        }
        .navigationTitle(NSLocalizedString("reset.title", comment: ""))
    }
}