import Foundation
import OSLog
import Network

/// Simple networking utility with retry logic.
enum NetworkError: Error {
    case offline
}

final class NetworkManager {
    static let shared = NetworkManager()
    private let logger = Logger(subsystem: "com.jimmy.app", category: "network")

    private init() {}

    /// Fetch data with optional retry attempts.
    /// - Parameters:
    ///   - request: The URL request to perform.
    ///   - retries: Number of additional attempts on failure.
    ///   - completion: Completion handler with result.
    func fetchData(with request: URLRequest,
                   retries: Int = 2,
                   completion: @escaping (Result<Data, Error>) -> Void) {
        guard NetworkMonitor.shared.isConnected else {
            completion(.failure(NetworkError.offline))
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logger.error("Request failed: \(error.localizedDescription, privacy: .public)")
                if retries > 0 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self?.fetchData(with: request, retries: retries - 1, completion: completion)
                    }
                } else {
                    completion(.failure(error))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                self?.logger.error("Unexpected status \(httpResponse.statusCode, privacy: .public)")
            }

            completion(.success(data ?? Data()))
        }.resume()
    }
}
