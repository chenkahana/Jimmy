import Foundation

/// Service for submitting feedback or bug reports to a remote endpoint.
/// Configure `endpointURL` with the URL of your Google Apps Script or server
/// that will append rows to your Google Sheet.
class FeedbackService {
    static let shared = FeedbackService()

    /// Replace with the URL of your Google Apps Script Web App
    var endpointURL: URL?

    private init() {}

    /// Submit feedback with a name and notes.
    /// - Parameters:
    ///   - name: Name of the person submitting
    ///   - notes: Feedback text or bug description
    ///   - completion: Called with `true` on success, `false` on failure
    func submit(name: String, notes: String, completion: @escaping (Bool) -> Void) {
        guard let url = endpointURL else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["name": name, "notes": notes]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                error == nil,
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            DispatchQueue.main.async { completion(true) }
        }.resume()
    }
}
