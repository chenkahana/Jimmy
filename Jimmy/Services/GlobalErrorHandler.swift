import SwiftUI
import OSLog

@MainActor
class GlobalErrorHandler: ObservableObject {
    @Published var currentError: UserFacingError?
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "ErrorHandler")
    
    func handle(_ error: Error, context: String) {
        logger.error("Error in \(context): \(error.localizedDescription)")
        
        let userError = UserFacingError(
            title: "Something went wrong",
            message: friendlyMessage(for: error),
            recoveryAction: recoveryAction(for: error)
        )
        
        currentError = userError
    }
    
    private func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Please check your internet connection and try again."
            case .timedOut:
                return "The request took too long. Please try again."
            case .cannotConnectToHost, .cannotFindHost:
                return "Unable to reach the server. Please try again later."
            case .cancelled:
                return "The request was cancelled."
            default:
                return "We encountered a network issue. Please try again."
            }
        }
        
        return "We encountered an unexpected issue. Please try again."
    }
    
    private func recoveryAction(for error: Error) -> (() -> Void)? {
        // Return appropriate recovery action based on error type
        return nil
    }
}

struct UserFacingError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let recoveryAction: (() -> Void)?
}
