import SwiftUI

/// A labeled text field with a single unified error label below it.
///
/// Follows Requirements U4: several similar errors collapse into one merged
/// message per field. The caller provides the merged message.
struct TextFieldWithError: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let submitLabel: SubmitLabel
    let autocapitalization: UITextAutocapitalizationType
    let accessibilityId: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            TextField(placeholder, text: $text)
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .autocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .padding()
                .background(Theme.backgroundSecondary)
                .cornerRadius(Theme.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(error != nil ? Theme.danger : Theme.hairline, lineWidth: 1)
                )
                .accessibilityIdentifier(accessibilityId)
                .onSubmit(onSubmit)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("\(accessibilityId)Error")
            }
        }
    }
}

#if DEBUG
private struct TextFieldWithErrorPreview: View {
    @State private var text: String = ""

    var body: some View {
        TextFieldWithError(
            title: "Email",
            placeholder: "Enter your email",
            text: $text,
            error: text.isEmpty ? "Email is required." : nil,
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            submitLabel: .continue,
            autocapitalization: .none,
            accessibilityId: "PreviewTextField"
        ) {}
        .padding()
    }
}

#Preview("Text Field With Error") {
    TextFieldWithErrorPreview()
}
#endif
