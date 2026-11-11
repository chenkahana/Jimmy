import Foundation

/// Service for submitting feedback or bug reports to a remote endpoint.
/// Configure `endpointURL` with the URL of your Google Apps Script or server
/// that will append rows to your Google Sheet.
class FeedbackService {
    static let shared = FeedbackService()

    /// URL for the Google Apps Script that writes to the feedback sheet
    /// Defaults to the shared demo script but can be replaced if needed.
    var endpointURL: URL? = URL(
        string: "https://script.google.com/macros/s/AKfycbz_lWE8VJGfqb1oIpvL9gzKcgS7O7OO8-cjL7t5y_qq5GH4KajHBaQwWkEKSafy8OHZ/exec"
    )

    private init() {}

    /// Submit feedback with a name and notes.
    /// - Parameters:
    ///   - name: Name of the person submitting
    ///   - notes: Feedback text or bug description
    ///   - completion: Called with a success flag and an optional message on failure
    func submit(name: String, notes: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = endpointURL else {
            completion(false, "No endpoint URL configured")
            return
        }

        let payload = ["name": name, "notes": notes]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false, "Failed to encode payload")
            return
        }

        Task {
            do {
                let data = try await UnifiedNetworkService.shared.postData(
                    url: url,
                    body: httpBody,
                    contentType: "application/json"
                )
                
                DispatchQueue.main.async { completion(true, nil) }
            } catch {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }
}
