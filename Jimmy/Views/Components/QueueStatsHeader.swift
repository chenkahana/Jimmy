import SwiftUI

struct QueueStatsHeader: View {
    let episodeCount: Int
    let totalRemainingTime: String

    var body: some View {
        Text("\(episodeCount) \(episodeCount == 1 ? "episode" : "episodes") · \(totalRemainingTime) left")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
    }
}
