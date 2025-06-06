import SwiftUI

/// Enables the interactive swipe gesture when using a custom back button.
/// This helper ensures the gesture is re-enabled whenever the view appears.
struct SwipeBackHelper: UIViewControllerRepresentable {
    final class HelperViewController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }

    func makeUIViewController(context: Context) -> UIViewController {
        HelperViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No update needed
    }
}
