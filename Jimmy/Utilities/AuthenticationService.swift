import Foundation

public enum LoginProvider {
    case apple
    case google
}

public struct AuthUser: Codable, Equatable {
    public let id: String
    public var name: String
    public var email: String?

    public init(id: String, name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }
}

/// Simple authentication service that provides placeholders for Sign in with
/// Apple or Google. On platforms where the respective frameworks are not
/// available, it returns a demo user immediately.
public class AuthenticationService: NSObject {
    public static let shared = AuthenticationService()
    private var completion: ((Result<AuthUser, Error>) -> Void)?

    private override init() {}

    /// Login with the given provider. This uses platform specific frameworks
    /// when available. On unsupported platforms a placeholder user is returned.
    public func login(with provider: LoginProvider, completion: @escaping (Result<AuthUser, Error>) -> Void) {
        self.completion = completion

        #if canImport(AuthenticationServices) && os(iOS)
        if provider == .apple {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
            return
        }
        #endif

        #if canImport(GoogleSignIn) && os(iOS)
        if provider == .google {
            GIDSignIn.sharedInstance.signIn(withPresenting: nil) { result, error in
                if let error = error {
                    completion(.failure(error))
                } else if let user = result?.user {
                    let authUser = AuthUser(id: user.userID ?? UUID().uuidString,
                                            name: user.profile?.name ?? "User",
                                            email: user.profile?.email)
                    completion(.success(authUser))
                } else {
                    completion(.failure(NSError(domain: "Auth", code: -1)))
                }
            }
            return
        }
        #endif

        // Fallback for unsupported platforms
        let demo = AuthUser(id: UUID().uuidString, name: "Demo User")
        completion(.success(demo))
    }
}

#if canImport(AuthenticationServices) && os(iOS)
import AuthenticationServices
extension AuthenticationService: ASAuthorizationControllerDelegate {
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let user = AuthUser(id: credential.user,
                                name: credential.fullName?.givenName ?? "User",
                                email: credential.email)
            completion?(.success(user))
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
    }
}
#endif
