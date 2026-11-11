import SwiftUI

/// Shown when the phone isn't reachable and hasn't sent any state yet — nothing to control and
/// nothing to show.
struct NotReachableView: View {
    var body: some View {
        ContentUnavailableView(
            "Open Jimmy on Your iPhone",
            systemImage: "iphone.gen3",
            description: Text("Jimmy needs your iPhone nearby to show what's playing.")
        )
    }
}
