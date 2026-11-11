import SwiftUI

struct EmptyStateView<Accessory: View>: View {
    let icon: String
    let eyebrow: String?
    let title: String
    let subtitle: String
    var primaryAction: JimmyEmptyStateAction?
    var secondaryAction: JimmyEmptyStateAction?
    let accessory: Accessory

    init(
        icon: String,
        eyebrow: String? = nil,
        title: String,
        subtitle: String,
        primaryAction: JimmyEmptyStateAction? = nil,
        secondaryAction: JimmyEmptyStateAction? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.icon = icon
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.accessory = accessory()
    }

    var body: some View {
        JimmyEmptyState(
            icon: icon,
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        ) {
            accessory
        }
    }
}
