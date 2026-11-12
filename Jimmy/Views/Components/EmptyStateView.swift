import SwiftUI

/// A system empty state: a symbol, a title, one sentence about what will appear, and at most two actions.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var primaryAction: JimmyEmptyStateAction?
    var secondaryAction: JimmyEmptyStateAction?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(subtitle)
        } actions: {
            if let primaryAction {
                JimmyPrimaryButton(
                    title: primaryAction.label,
                    systemImage: primaryAction.systemImage,
                    action: primaryAction.action
                )
            }

            if let secondaryAction {
                Button(secondaryAction.label, action: secondaryAction.action)
            }
        }
    }
}
