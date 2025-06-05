import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Combine)
import Combine
#endif
#if canImport(GoogleSignIn) && os(iOS)
import GoogleSignIn
#endif

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
#if canImport(Combine)
    @Published public private(set) var currentUser: AuthUser?
#else
    public private(set) var currentUser: AuthUser?
#endif
    public static let shared = AuthenticationService()
    private var completion: ((Result<AuthUser, Error>) -> Void)?
    private let userKey = "authUser"

    private override init() {
        if let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            currentUser = user
        }
    }

    /// Login with the given provider. This uses platform specific frameworks
    /// when available. On unsupported platforms a placeholder user is returned.
    public func login(with provider: LoginProvider, completion: @escaping (Result<AuthUser, Error>) -> Void) {
        self.completion = { result in
            if case .success(let user) = result {
                self.currentUser = user
                if let data = try? JSONEncoder().encode(user) {
                    UserDefaults.standard.set(data, forKey: self.userKey)
                }
            }
            completion(result)
        }

        #if canImport(AuthenticationServices) && os(iOS)
        if provider == .apple {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
            return
        }
        #endif

        #if canImport(GoogleSignIn) && os(iOS)
        if provider == .google {
            guard let presentingVC = UIApplication.topViewController else {
                let error = NSError(domain: "Auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "No presenting view controller"])
                self.completion?(.failure(error))
                return
            }
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC) { result, error in
                if let error = error {
                    self.completion?(.failure(error))
                } else if let user = result?.user {
                    let authUser = AuthUser(id: user.userID ?? UUID().uuidString,
                                            name: user.profile?.name ?? "User",
                                            email: user.profile?.email)
                    self.completion?(.success(authUser))
                } else {
                    self.completion?(.failure(NSError(domain: "Auth", code: -1)))
                }
            }
            return
        }
        #endif

        // Fallback for unsupported platforms
        let demo = AuthUser(id: UUID().uuidString, name: "Demo User")
        self.completion?(.success(demo))
    }

    public func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: userKey)
    }
}

#if canImport(Combine)
extension AuthenticationService: ObservableObject {}
#endif

#if canImport(AuthenticationServices) && os(iOS)
import AuthenticationServices
extension AuthenticationService: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
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

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}
#endif
