import SwiftUI

/// Shared presentation shell for editor sheets with a native collapsing title,
/// cancellation action, scrollable content, and keyboard-safe bottom action bar.
struct EditorSheetScaffold<Content: View, BottomBar: View>: View {
    let title: String
    let cancelTitle: String
    let isLoading: Bool
    let cancelAccessibilityId: String
    let usesMediumDetent: Bool
    let onCancel: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let bottomBar: BottomBar

    @State private var bottomBarHeight: CGFloat = 0

    init(
        title: String,
        cancelTitle: String,
        isLoading: Bool,
        cancelAccessibilityId: String,
        usesMediumDetent: Bool,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.isLoading = isLoading
        self.cancelAccessibilityId = cancelAccessibilityId
        self.usesMediumDetent = usesMediumDetent
        self.onCancel = onCancel
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *), usesMediumDetent {
                sheetContent
                    .presentationDetents([.medium, .large])
            } else {
                sheetContent
            }
        }
    }

    private var sheetContent: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                    content

                    Theme.transparent
                        .frame(height: bottomBarHeight + Theme.spacingLarge)
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundPrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle, action: onCancel)
                        .disabled(isLoading)
                        .accessibilityIdentifier(cancelAccessibilityId)
                }
            }
            .measuredBottomBar(height: $bottomBarHeight) {
                bottomBar
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(isLoading)
    }
}
