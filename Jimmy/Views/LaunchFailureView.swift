import SwiftUI

/// Shown instead of the normal app content when `AppModel` couldn't open the database. The old
/// services are never started while this is on screen (see `JimmyApp`).
struct LaunchFailureView: View {
    let message: String
    let onRetry: () -> Void
    let onResetLibrary: () -> Void

    @State private var isShowingResetConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Jimmy couldn't open your library")
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)

            Button("Reset Library", role: .destructive) {
                isShowingResetConfirmation = true
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .alert("Reset library?", isPresented: $isShowingResetConfirmation) {
            Button("Reset", role: .destructive, action: onResetLibrary)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the current database aside and starts a new, empty library. The old file is kept, not deleted.")
        }
    }
}
