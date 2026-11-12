//
//  DesignSystem.swift
//  Jimmy
//
//  Tokens and shared pieces for Jimmy's look. The rules are in docs/design.md:
//  system colors, one accent, color from artwork, no decoration.
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

    /// The only shadow: under artwork that floats, such as the Now Playing art.
    enum Shadow {
        static let artworkColor = Color.black.opacity(0.18)
        static let artworkRadius: CGFloat = 20
        static let artworkY: CGFloat = 8
    }

    enum Typography {
        static let largeTitle = Font.title2.weight(.semibold)
        static let title = Font.headline
        static let body = Font.subheadline
        static let caption = Font.caption.weight(.medium)
        static let detail = Font.caption2
    }

    enum Palette {
        static let canvas = Color(uiColor: .systemGroupedBackground)
        static let canvasElevated = Color(uiColor: .secondarySystemGroupedBackground)
        static let fieldFill = Color(uiColor: .tertiarySystemFill)
        static let divider = Color(uiColor: .separator)
        static let mutedText = Color.secondary
    }
}

/// A flat grouped surface, like a row group in an inset-grouped list. No border, no shadow.
struct JimmyCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            JimmyDesign.Palette.canvasElevated,
            in: RoundedRectangle(cornerRadius: JimmyDesign.Radius.lg, style: .continuous)
        )
    }
}

extension View {
    func jimmyCard() -> some View {
        modifier(JimmyCardStyle())
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
        JimmyDesign.Palette.canvas.ignoresSafeArea()
    }
}

struct JimmyCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = JimmyDesign.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .jimmyCard()
    }
}

struct JimmySectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    init(_ title: String, subtitle: String? = nil) where Trailing == EmptyView {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JimmyDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: JimmyDesign.Spacing.md)

            trailing
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
        HStack(spacing: JimmyDesign.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
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
        .padding(.horizontal, JimmyDesign.Spacing.md)
        .padding(.vertical, JimmyDesign.Spacing.sm)
        .background(JimmyDesign.Palette.fieldFill, in: Capsule())
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
            if isLoading {
                HStack(spacing: JimmyDesign.Spacing.sm) {
                    ProgressView()
                    Text(title)
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(isLoading)
    }
}

struct JimmySecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}
