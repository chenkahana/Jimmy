import SwiftUI

#if canImport(UIKit)
extension View {
    /// Dismisses the active keyboard.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Adds a "Close" button above the keyboard to allow dismissal.
    func keyboardDismissToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Close") { hideKeyboard() }
            }
        }
    }
}
#endif
