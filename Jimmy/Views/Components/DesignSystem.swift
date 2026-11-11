//
//  DesignSystem.swift
//  Jimmy
//
//  Centralized design tokens and shared UI primitives for the shipping app.
//

import SwiftUI

enum JimmyDesign {

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Shadow {
        static let cardColor = Color.black.opacity(0.08)
        static let cardRadius: CGFloat = 12
        static let cardY: CGFloat = 4

        static let elevatedColor = Color.black.opacity(0.15)
        static let elevatedRadius: CGFloat = 20
        static let elevatedY: CGFloat = 8
    }

    enum Typography {
        static let hero = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let largeTitle = Font.title2.weight(.semibold)
        static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)
        static let title = Font.headline
        static let body = Font.subheadline
        static let caption = Font.caption.weight(.medium)
        static let detail = Font.caption2
    }

    enum Palette {
        static let canvas = Color(uiColor: .systemGroupedBackground)
        static let canvasElevated = Color(uiColor: .secondarySystemGroupedBackground)
        static let backgroundTop = Color(uiColor: .systemBackground)
        static let backgroundBottom = Color(uiColor: .systemGroupedBackground)
        static let fieldFill = Color(uiColor: .tertiarySystemFill)
        static let divider = Color.primary.opacity(0.08)
        static let mutedText = Color.secondary
        static let accentGlow = Color.accentColor.opacity(0.18)
        static let warmGlow = Color.orange.opacity(0.12)
        static let surface = Color(uiColor: .secondarySystemBackground).opacity(0.72)
        static let mutedBorder = Color.white.opacity(0.18)
    }

    enum Glass {
        static let cardMaterial: Material = .regularMaterial
        static let cardBorder = Color.white.opacity(0.12)
        static let cardBorderWidth: CGFloat = 0.5
    }
}

struct JimmyCardStyle: ViewModifier {
    var isHighlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: JimmyDesign.Radius.lg, style: .continuous)
                    .fill(JimmyDesign.Glass.cardMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: JimmyDesign.Radius.lg, style: .continuous)
                            .stroke(
                                isHighlighted ? Color.accentColor.opacity(0.3) : JimmyDesign.Glass.cardBorder,
                                lineWidth: isHighlighted ? 1.5 : JimmyDesign.Glass.cardBorderWidth
                            )
                    )
                    .shadow(
                        color: JimmyDesign.Shadow.cardColor,
                        radius: JimmyDesign.Shadow.cardRadius,
                        x: 0,
                        y: JimmyDesign.Shadow.cardY
                    )
            )
    }
}

extension View {
    func jimmyCard(isHighlighted: Bool = false) -> some View {
        modifier(JimmyCardStyle(isHighlighted: isHighlighted))
    }
}

struct JimmyButtonAction {
    let label: String
    let systemImage: String
    let action: () -> Void
}

typealias JimmyEmptyStateAction = JimmyButtonAction

struct JimmyScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    JimmyDesign.Palette.backgroundTop,
                    JimmyDesign.Palette.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(JimmyDesign.Palette.accentGlow)
                .frame(width: 260, height: 260)
                .blur(radius: 44)
                .offset(x: 140, y: -220)

            Circle()
                .fill(JimmyDesign.Palette.warmGlow)
                .frame(width: 220, height: 220)
                .blur(radius: 54)
                .offset(x: -140, y: -130)
        }
        .ignoresSafeArea()
    }
}

struct JimmyCard<Content: View>: View {
    private let content: Content
    private let isHighlighted: Bool
    private let padding: CGFloat

    init(
        isHighlighted: Bool = false,
        padding: CGFloat = JimmyDesign.Spacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.isHighlighted = isHighlighted
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .jimmyCard(isHighlighted: isHighlighted)
    }
}

struct JimmySectionHeader<Trailing: View>: View {
    private let eyebrow: String?
    private let title: String
    private let subtitle: String?
    private let icon: String?
    private let tint: Color
    private let trailingText: String?
    private let trailing: Trailing

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        tint: Color = .accentColor,
        trailingText: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.trailingText = trailingText
        self.trailing = trailing()
    }

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        tint: Color = .accentColor,
        trailingText: String? = nil
    ) where Trailing == EmptyView {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: tint,
            trailingText: trailingText
        ) {
            EmptyView()
        }
    }

    init(
        title: String,
        detail: String,
        icon: String
    ) where Trailing == EmptyView {
        self.init(
            eyebrow: nil,
            title: title,
            subtitle: detail,
            icon: icon,
            tint: .accentColor,
            trailingText: nil
        )
    }

    init(
        title: String,
        icon: String,
        trailingText: String
    ) where Trailing == EmptyView {
        self.init(
            eyebrow: nil,
            title: title,
            subtitle: nil,
            icon: icon,
            tint: .accentColor,
            trailingText: trailingText
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: JimmyDesign.Spacing.md) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 34, height: 34)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .padding(.top, subtitle == nil ? 2 : 0)
            }

            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(JimmyDesign.Typography.caption)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(subtitle == nil ? JimmyDesign.Typography.sectionTitle : JimmyDesign.Typography.largeTitle)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(JimmyDesign.Typography.body)
                        .foregroundStyle(JimmyDesign.Palette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: JimmyDesign.Spacing.md)

            if let trailingText, !trailingText.isEmpty {
                Text(trailingText.uppercased())
                    .font(JimmyDesign.Typography.caption)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                trailing
            }
        }
    }
}

struct JimmySearchField: View {
    @Binding var text: String
    let placeholder: String
    let prompt: String
    let accessibilityLabel: String?
    let icon: String
    private let focus: FocusState<Bool>.Binding?

    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String = "Search",
        prompt: String? = nil,
        accessibilityLabel: String? = nil,
        focus: FocusState<Bool>.Binding? = nil,
        icon: String = "magnifyingglass"
    ) {
        self._text = text
        self.placeholder = placeholder
        self.prompt = prompt ?? placeholder
        self.accessibilityLabel = accessibilityLabel
        self.focus = focus
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: JimmyDesign.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(isSearchFocused ? Color.accentColor : JimmyDesign.Palette.mutedText)
                .accessibilityHidden(true)

            searchInput

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, JimmyDesign.Spacing.lg)
        .padding(.vertical, JimmyDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                .fill(JimmyDesign.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                .stroke(
                    isSearchFocused ? Color.accentColor.opacity(0.35) : JimmyDesign.Palette.mutedBorder,
                    lineWidth: isSearchFocused ? 1.2 : 0.6
                )
        )
        .animation(.easeInOut(duration: 0.18), value: isSearchFocused)
    }

    private var isSearchFocused: Bool {
        focus?.wrappedValue ?? isFocused
    }

    @ViewBuilder
    private var searchInput: some View {
        if let focus {
            TextField(prompt, text: $text, prompt: Text(placeholder).foregroundStyle(.secondary))
                .focused(focus)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel(accessibilityLabel ?? placeholder)
        } else {
            TextField(prompt, text: $text, prompt: Text(placeholder).foregroundStyle(.secondary))
                .focused($isFocused)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel(accessibilityLabel ?? placeholder)
        }
    }
}

struct JimmyPrimaryButton: View {
    let title: String
    let systemImage: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: JimmyDesign.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                }

                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, JimmyDesign.Spacing.lg)
            .padding(.vertical, JimmyDesign.Spacing.md)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.76)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct JimmySecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: JimmyDesign.Spacing.sm) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, JimmyDesign.Spacing.lg)
            .padding(.vertical, JimmyDesign.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                    .stroke(JimmyDesign.Palette.mutedBorder, lineWidth: 0.6)
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

struct JimmyEmptyState<Accessory: View>: View {
    let icon: String
    let eyebrow: String?
    let title: String
    let subtitle: String
    var primaryAction: JimmyButtonAction?
    var secondaryAction: JimmyButtonAction?
    private let accessory: Accessory

    init(
        icon: String,
        eyebrow: String? = nil,
        title: String,
        subtitle: String,
        primaryAction: JimmyButtonAction? = nil,
        secondaryAction: JimmyButtonAction? = nil,
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
        VStack(spacing: JimmyDesign.Spacing.xl) {
            JimmyCard(isHighlighted: true, padding: JimmyDesign.Spacing.xl) {
                VStack(spacing: JimmyDesign.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 100, height: 100)

                        Circle()
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            .frame(width: 116, height: 116)

                        Image(systemName: icon)
                            .font(.system(size: 40, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(spacing: JimmyDesign.Spacing.sm) {
                        if let eyebrow, !eyebrow.isEmpty {
                            Text(eyebrow.uppercased())
                                .font(JimmyDesign.Typography.caption)
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                        }

                        Text(title)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(JimmyDesign.Palette.mutedText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: JimmyDesign.Spacing.sm) {
                        if let primaryAction {
                            JimmyPrimaryButton(
                                title: primaryAction.label,
                                systemImage: primaryAction.systemImage,
                                action: primaryAction.action
                            )
                        }

                        if let secondaryAction {
                            JimmySecondaryButton(
                                title: secondaryAction.label,
                                systemImage: secondaryAction.systemImage,
                                action: secondaryAction.action
                            )
                        }
                    }
                    .frame(maxWidth: 320)
                }
            }
            .frame(maxWidth: 640)

            accessory
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(JimmyDesign.Spacing.xl)
        .background(JimmyScreenBackground())
    }
}
