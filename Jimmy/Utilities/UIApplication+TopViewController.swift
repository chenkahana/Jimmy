#if canImport(UIKit)
import UIKit

extension UIApplication {
    /// Returns the top-most presented view controller, if any.
    static var topViewController: UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
