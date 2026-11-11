import SwiftUI
import UIKit
import Combine

/// Comprehensive user feedback service for enhanced user experience
/// Manages toasts, alerts, haptic feedback, and contextual messages
@MainActor
class UserFeedbackService: ObservableObject {
    static let shared = UserFeedbackService()
    
    // MARK: - Published Properties
    
    @Published var activeToasts: [ToastMessage] = []
    @Published var activeAlerts: [AlertMessage] = []
    @Published var isShowingBanner: Bool = false
    @Published var currentBanner: BannerMessage?
    
    // MARK: - Private Properties
    
    private var toastQueue: [ToastMessage] = []
    private var cancellables = Set<AnyCancellable>()
    private let maxSimultaneousToasts = 3
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    // MARK: - Initialization
    
    private init() {
        setupToastManagement()
        prepareHapticGenerator()
    }
    
    // MARK: - Toast Messages
    
    struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let type: ToastType
        let duration: TimeInterval
        let action: ToastAction?
        let hapticFeedback: HapticType?
        
        enum ToastType {
            case success
            case error
            case warning
            case info
            case loading
            
            var color: Color {
                switch self {
                case .success: return .green
                case .error: return .red
                case .warning: return .orange
                case .info: return .blue
                case .loading: return .gray
                }
            }
            
            var icon: String {
                switch self {
                case .success: return "checkmark.circle.fill"
                case .error: return "xmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .info: return "info.circle.fill"
                case .loading: return "clock.fill"
                }
            }
        }
        
        struct ToastAction {
            let title: String
            let action: () -> Void
        }
        
        static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    /// Show a toast message with optional action and haptic feedback
    func showToast(
        _ message: String,
        type: ToastMessage.ToastType = .info,
        duration: TimeInterval = 3.0,
        action: ToastMessage.ToastAction? = nil,
        hapticFeedback: HapticType? = nil
    ) {
        let toast = ToastMessage(
            message: message,
            type: type,
            duration: duration,
            action: action,
            hapticFeedback: hapticFeedback
        )
        
        // Trigger haptic feedback if specified
        if let haptic = hapticFeedback {
            triggerHapticFeedback(haptic)
        }
        
        // Add to queue or display immediately
        if activeToasts.count < maxSimultaneousToasts {
            displayToast(toast)
        } else {
            toastQueue.append(toast)
        }
    }
    
    /// Show success toast with haptic feedback
    func showSuccess(_ message: String, action: ToastMessage.ToastAction? = nil) {
        showToast(message, type: .success, action: action, hapticFeedback: .success)
    }
    
    /// Show error toast with haptic feedback
    func showError(_ message: String, action: ToastMessage.ToastAction? = nil) {
        showToast(message, type: .error, action: action, hapticFeedback: .error)
    }
    
    /// Show warning toast
    func showWarning(_ message: String, action: ToastMessage.ToastAction? = nil) {
        showToast(message, type: .warning, action: action, hapticFeedback: .warning)
    }
    
    /// Show info toast
    func showInfo(_ message: String, action: ToastMessage.ToastAction? = nil) {
        showToast(message, type: .info, action: action)
    }
    
    private func displayToast(_ toast: ToastMessage) {
        activeToasts.append(toast)
        
        // Auto-dismiss after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration) {
            self.dismissToast(toast)
        }
    }
    
    func dismissToast(_ toast: ToastMessage) {
        activeToasts.removeAll { $0.id == toast.id }
        
        // Show next toast in queue if available
        if !toastQueue.isEmpty {
            let nextToast = toastQueue.removeFirst()
            displayToast(nextToast)
        }
    }
    
    /// Dismiss all active toasts
    func dismissAllToasts() {
        activeToasts.removeAll()
        toastQueue.removeAll()
    }
    
    // MARK: - Alert Messages
    
    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
        let primaryAction: AlertAction
        let secondaryAction: AlertAction?
        let style: AlertStyle
        
        enum AlertStyle {
            case standard
            case destructive
            case informational
        }
        
        struct AlertAction {
            let title: String
            let style: ActionStyle
            let action: () -> Void
            
            enum ActionStyle {
                case `default`
                case cancel
                case destructive
            }
        }
    }
    
    /// Show an alert with customizable actions
    func showAlert(
        title: String,
        message: String? = nil,
        primaryAction: AlertMessage.AlertAction,
        secondaryAction: AlertMessage.AlertAction? = nil,
        style: AlertMessage.AlertStyle = .standard
    ) {
        let alert = AlertMessage(
            title: title,
            message: message,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            style: style
        )
        
        activeAlerts.append(alert)
    }
    
    /// Show confirmation alert
    func showConfirmation(
        title: String,
        message: String,
        confirmTitle: String = "Confirm",
        cancelTitle: String = "Cancel",
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        showAlert(
            title: title,
            message: message,
            primaryAction: AlertMessage.AlertAction(
                title: confirmTitle,
                style: .default,
                action: onConfirm
            ),
            secondaryAction: AlertMessage.AlertAction(
                title: cancelTitle,
                style: .cancel,
                action: onCancel ?? {}
            )
        )
    }
    
    /// Show destructive confirmation alert
    func showDestructiveConfirmation(
        title: String,
        message: String,
        destructiveTitle: String = "Delete",
        cancelTitle: String = "Cancel",
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        showAlert(
            title: title,
            message: message,
            primaryAction: AlertMessage.AlertAction(
                title: destructiveTitle,
                style: .destructive,
                action: onConfirm
            ),
            secondaryAction: AlertMessage.AlertAction(
                title: cancelTitle,
                style: .cancel,
                action: onCancel ?? {}
            ),
            style: .destructive
        )
    }
    
    /// Dismiss alert
    func dismissAlert(_ alert: AlertMessage) {
        activeAlerts.removeAll { $0.id == alert.id }
    }
    
    // MARK: - Banner Messages
    
    struct BannerMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let type: BannerType
        let action: BannerAction?
        let autoDismiss: Bool
        let duration: TimeInterval
        
        enum BannerType {
            case info
            case warning
            case error
            case success
            case update
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .warning: return .orange
                case .error: return .red
                case .success: return .green
                case .update: return .purple
                }
            }
            
            var icon: String {
                switch self {
                case .info: return "info.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error: return "xmark.circle.fill"
                case .success: return "checkmark.circle.fill"
                case .update: return "arrow.down.circle.fill"
                }
            }
        }
        
        struct BannerAction {
            let title: String
            let action: () -> Void
        }
    }
    
    /// Show a banner message
    func showBanner(
        title: String,
        message: String,
        type: BannerMessage.BannerType = .info,
        action: BannerMessage.BannerAction? = nil,
        autoDismiss: Bool = true,
        duration: TimeInterval = 5.0
    ) {
        let banner = BannerMessage(
            title: title,
            message: message,
            type: type,
            action: action,
            autoDismiss: autoDismiss,
            duration: duration
        )
        
        currentBanner = banner
        isShowingBanner = true
        
        if autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.dismissBanner()
            }
        }
    }
    
    /// Dismiss current banner
    func dismissBanner() {
        isShowingBanner = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentBanner = nil
        }
    }
    
    // MARK: - Haptic Feedback
    
    enum HapticType {
        case success
        case warning
        case error
        case light
        case medium
        case heavy
        case selection
        
        var notificationFeedback: UINotificationFeedbackGenerator.FeedbackType? {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            default: return nil
            }
        }
        
        var impactFeedback: UIImpactFeedbackGenerator.FeedbackStyle? {
            switch self {
            case .light: return .light
            case .medium: return .medium
            case .heavy: return .heavy
            default: return nil
            }
        }
    }
    
    /// Trigger haptic feedback
    func triggerHapticFeedback(_ type: HapticType) {
        switch type {
        case .success, .warning, .error:
            if let feedbackType = type.notificationFeedback {
                hapticGenerator.notificationOccurred(feedbackType)
            }
        case .light, .medium, .heavy:
            if let feedbackStyle = type.impactFeedback {
                let impactGenerator = UIImpactFeedbackGenerator(style: feedbackStyle)
                impactGenerator.impactOccurred()
            }
        case .selection:
            let selectionGenerator = UISelectionFeedbackGenerator()
            selectionGenerator.selectionChanged()
        }
    }
    
    // MARK: - Progress Feedback
    
    struct ProgressFeedback: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
        let progress: Double
        let isIndeterminate: Bool
        let canCancel: Bool
        let onCancel: (() -> Void)?
    }
    
    @Published var activeProgress: ProgressFeedback?
    
    /// Show progress feedback
    func showProgress(
        title: String,
        message: String? = nil,
        progress: Double = 0.0,
        isIndeterminate: Bool = false,
        canCancel: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        activeProgress = ProgressFeedback(
            title: title,
            message: message,
            progress: progress,
            isIndeterminate: isIndeterminate,
            canCancel: canCancel,
            onCancel: onCancel
        )
    }
    
    /// Update progress
    func updateProgress(_ progress: Double, message: String? = nil) {
        guard let currentProgress = activeProgress else { return }
        
        activeProgress = ProgressFeedback(
            title: currentProgress.title,
            message: message ?? currentProgress.message,
            progress: progress,
            isIndeterminate: currentProgress.isIndeterminate,
            canCancel: currentProgress.canCancel,
            onCancel: currentProgress.onCancel
        )
    }
    
    /// Dismiss progress feedback
    func dismissProgress() {
        activeProgress = nil
    }
    
    // MARK: - Private Methods
    
    private func setupToastManagement() {
        // Monitor toast queue and manage display
        $activeToasts
            .sink { toasts in
                // Manage toast positioning and animations
            }
            .store(in: &cancellables)
    }
    
    private func prepareHapticGenerator() {
        hapticGenerator.prepare()
    }
}

// MARK: - SwiftUI Integration

/// Toast overlay view for displaying toast messages
struct ToastOverlay: View {
    @ObservedObject private var feedbackService = UserFeedbackService.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(feedbackService.activeToasts) { toast in
                EnhancedToastView(toast: toast) {
                    feedbackService.dismissToast(toast)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
            
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: feedbackService.activeToasts)
    }
}

/// Individual toast view
struct EnhancedToastView: View {
    let toast: UserFeedbackService.ToastMessage
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: toast.type.icon)
                .font(.title3)
                .foregroundColor(toast.type.color)
            
            // Message
            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            // Action button if available
            if let action = toast.action {
                Button(action.title, action: action.action)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(toast.type.color)
            }
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .scaleEffect(isVisible ? 1.0 : 0.9)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

/// Banner overlay view
struct BannerOverlay: View {
    @ObservedObject private var feedbackService = UserFeedbackService.shared
    
    var body: some View {
        VStack {
            if feedbackService.isShowingBanner, let banner = feedbackService.currentBanner {
                BannerView(banner: banner) {
                    feedbackService.dismissBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: feedbackService.isShowingBanner)
    }
}

/// Individual banner view
struct BannerView: View {
    let banner: UserFeedbackService.BannerMessage
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: banner.type.icon)
                .font(.title2)
                .foregroundColor(banner.type.color)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(banner.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action button if available
            if let action = banner.action {
                Button(action.title, action: action.action)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(banner.type.color)
            }
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(banner.type.color.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

/// Progress overlay view
struct ProgressOverlay: View {
    @ObservedObject private var feedbackService = UserFeedbackService.shared
    
    var body: some View {
        if let progress = feedbackService.activeProgress {
            ZStack {
                // Background overlay
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // Progress view
                ContextualLoadingIndicator(
                    type: .contentLoading,
                    message: progress.title,
                    progress: progress.isIndeterminate ? nil : progress.progress,
                    showCancel: progress.canCancel,
                    onCancel: progress.onCancel
                )
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: feedbackService.activeProgress != nil)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Add feedback overlays to any view
    func withFeedbackOverlays() -> some View {
        self
            .overlay(ToastOverlay(), alignment: .top)
            .overlay(BannerOverlay(), alignment: .top)
            .overlay(ProgressOverlay())
    }
}