import SwiftUI

/// Enables the interactive swipe gesture when using a custom back button.
struct SwipeBackHelper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            controller.navigationController?.interactivePopGestureRecognizer?.delegate = nil
            controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.delegate = nil
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
