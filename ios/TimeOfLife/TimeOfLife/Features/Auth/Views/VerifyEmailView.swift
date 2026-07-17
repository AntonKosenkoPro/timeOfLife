import SwiftUI

struct VerifyEmailView: View {
    @ObservedObject var vm: VerifyEmailViewModel

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("verify.token", comment: ""), text: $vm.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("VerifyToken")
            }
            Section {
                Button {
                    Task { await vm.submit() }
                } label: {
                    HStack {
                        if vm.isSubmitting { ProgressView() }
                        Text(NSLocalizedString("verify.submit", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.isSubmitting || vm.isOffline)
                .accessibilityIdentifier("VerifySubmit")

                Button {
                    Task { await vm.resend() }
                } label: {
                    Text(NSLocalizedString("verify.resend", comment: ""))
                        .frame(maxWidth: .infinity)
                }
                .disabled(vm.isSubmitting || vm.isOffline)
                .accessibilityIdentifier("VerifyResend")
            }
            if let success = vm.successMessage {
                Section { Text(success).foregroundStyle(Theme.success) }
                    .accessibilityIdentifier("VerifySuccess")
            }
            if let error = vm.submitError {
                Section { Text(error).foregroundStyle(Theme.danger) }
                    .accessibilityIdentifier("VerifySubmitError")
            }
        }
        .navigationTitle(NSLocalizedString("verify.title", comment: ""))
    }
}