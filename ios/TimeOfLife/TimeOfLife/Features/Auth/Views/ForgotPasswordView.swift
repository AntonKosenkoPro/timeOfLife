import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject var vm: ForgotPasswordViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("forgot.email", comment: ""), text: $vm.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("ForgotEmail")
            }
            if !vm.fieldErrors.email.isEmpty {
                ErrorSection(messages: vm.fieldErrors.email)
            }
            Section {
                Button {
                    Task { await vm.submit() }
                } label: {
                    HStack {
                        if vm.isSubmitting { ProgressView() }
                        Text(NSLocalizedString("forgot.submit", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.isSubmitting || vm.isOffline)
                .accessibilityIdentifier("ForgotSubmit")
            }
            if let success = vm.successMessage {
                Section { Text(success).foregroundStyle(Theme.success) }
                    .accessibilityIdentifier("ForgotSuccess")
            }
            if let error = vm.submitError {
                Section { Text(error).foregroundStyle(Theme.danger) }
                    .accessibilityIdentifier("ForgotSubmitError")
            }
        }
        .navigationTitle(NSLocalizedString("forgot.title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("forgot.back", comment: "")) { dismiss() }
                    .accessibilityIdentifier("ForgotBack")
            }
        }
    }
}